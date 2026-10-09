#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools release preflight'

usage() {
  cat <<'HELP'
Usage: bash packaging/release/check-preflight.sh \
  --mode pretag|tagged --date YYYY-MM-DD --expect-head FULL_COMMIT_SHA

Read-only local release-source checks:
  - require a clean Git checkout at the expected exact commit;
  - verify stable VERSION and both CLI version commands;
  - verify the unique, exactly dated CHANGELOG heading;
  - pretag: require no local vVERSION tag;
  - tagged: require an annotated local vVERSION tag resolving to HEAD.

An intended date must be supplied explicitly; it is never inferred or written.
This checks LOCAL state only. It does not verify remote tags, CI, release
assets, signing, or publication. It never creates tags or modifies files.
HELP
}

fail() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

mode='' release_date='' expected_head=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      [ "$#" -ge 2 ] || fail '--mode requires pretag or tagged'
      mode=$2
      shift 2
      ;;
    --date)
      [ "$#" -ge 2 ] || fail '--date requires YYYY-MM-DD'
      release_date=$2
      shift 2
      ;;
    --expect-head)
      [ "$#" -ge 2 ] || fail '--expect-head requires the full reviewed commit SHA'
      expected_head=$2
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      fail 'unrecognized argument (use --help)'
      ;;
  esac
done

case "$mode" in
  pretag|tagged) ;;
  *) fail 'explicit --mode pretag|tagged is required' ;;
esac

[[ "$release_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || \
  fail 'explicit --date must use YYYY-MM-DD'
IFS=- read -r year month day <<< "$release_date"
year_number=$((10#$year))
month_number=$((10#$month))
day_number=$((10#$day))
[ "$year_number" -gt 0 ] || fail 'date year must be greater than zero'
if [ "$month_number" -lt 1 ] || [ "$month_number" -gt 12 ]; then
  fail 'invalid calendar month'
fi
days_in_month=31
case "$month_number" in
  4|6|9|11) days_in_month=30 ;;
  2)
    days_in_month=28
    if (( year_number % 4 == 0 && (year_number % 100 != 0 || year_number % 400 == 0) )); then
      days_in_month=29
    fi
    ;;
esac
if [ "$day_number" -lt 1 ] || [ "$day_number" -gt "$days_in_month" ]; then
  fail 'invalid calendar day'
fi

[[ "$expected_head" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || \
  fail '--expect-head requires a full lowercase 40- or 64-character commit SHA'

command -v git >/dev/null 2>&1 || fail 'git is required'
root=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd -P)
git_root=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || \
  fail 'run this preflight from a Git source checkout'
git_root=$(cd -- "$git_root" && pwd -P)
[ "$git_root" = "$root" ] || fail 'release preflight must be inside its own Git checkout root'

actual_head=$(git -C "$root" rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || \
  fail 'HEAD is not a valid commit'
[ "$actual_head" = "$expected_head" ] || \
  fail "HEAD differs from --expect-head ($actual_head)"

dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$root" status --porcelain --untracked-files=all) || \
  fail 'unable to inspect Git working tree'
[ -z "$dirty" ] || fail 'Git working tree/index has changes or untracked files'

[ -r "$root/VERSION" ] || fail 'VERSION file is missing'
version=$(cat "$root/VERSION")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  fail 'VERSION must be a stable MAJOR.MINOR.PATCH release value'
expected_cli="pantheon-local $version"
[ -r "$root/bin/pantheon-local" ] || fail 'CLI entry point is unavailable'
cli_version=$(bash "$root/bin/pantheon-local" version) || fail 'CLI version command failed'
cli_flag=$(bash "$root/bin/pantheon-local" --version) || fail 'CLI --version command failed'
[ "$cli_version" = "$expected_cli" ] || fail 'CLI version output does not match VERSION'
[ "$cli_flag" = "$expected_cli" ] || fail 'CLI --version output does not match VERSION'

[ -r "$root/CHANGELOG.md" ] || fail 'CHANGELOG.md is unavailable'
expected_heading="## $version — $release_date"
heading_count=$(awk -v version="$version" '$1 == "##" && $2 == version { count++ } END { print count+0 }' "$root/CHANGELOG.md") || \
  fail 'cannot inspect changelog headings'
[ "$heading_count" -eq 1 ] || \
  fail "CHANGELOG.md must contain exactly one section for $version"
exact_count=$(LC_ALL=C grep -Fxc -- "$expected_heading" "$root/CHANGELOG.md" || true)
[ "$exact_count" = 1 ] || \
  fail "CHANGELOG.md heading must exactly match: $expected_heading"

tag="v$version"
tag_ref="refs/tags/$tag"
tag_status=0
git -C "$root" show-ref --verify --quiet "$tag_ref" || tag_status=$?
case "$mode:$tag_status" in
  pretag:1)
    ;;
  pretag:0)
    fail "local $tag already exists; pretag mode requires it to be absent"
    ;;
  tagged:0)
    object_type=$(git -C "$root" cat-file -t "$tag_ref" 2>/dev/null) || \
      fail "cannot read local $tag object"
    [ "$object_type" = tag ] || fail "$tag must be an annotated Git tag"
    tag_head=$(git -C "$root" rev-parse --verify "$tag_ref^{commit}" 2>/dev/null) || \
      fail "cannot peel local $tag to a commit"
    [ "$tag_head" = "$actual_head" ] || \
      fail "$tag does not resolve to the expected HEAD"
    ;;
  tagged:1)
    fail "local annotated $tag is required in tagged mode"
    ;;
  *)
    fail "unable to inspect local $tag ref"
    ;;
esac

printf 'Local release preflight\n'
printf '  Mode:       %s\n' "$mode"
printf '  Version:    %s\n' "$version"
printf '  Date:       %s\n' "$release_date"
printf '  Commit:     %s\n' "$actual_head"
printf '  Local tag:  %s\n' "$([ "$mode" = pretag ] && printf absent || printf 'annotated/matched')"
printf 'LOCAL_PREFLIGHT=PASS\n'
printf 'Not checked: remote Git refs, GitHub CI, releases, signing, artifacts or publication.\n'
