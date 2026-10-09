#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
PREFLIGHT="$REPO_ROOT/packaging/release/check-preflight.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

# A fixture must not depend on a maintainer's Git identity or global config.
export HOME="$TMP_ROOT/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

FIXTURE='' OUTPUT='' RC=0
make_fixture() {
  local label=$1
  FIXTURE="$TMP_ROOT/$label"
  mkdir -p "$FIXTURE/bin" "$FIXTURE/packaging/release"
  cp "$REPO_ROOT/bin/pantheon-local" "$FIXTURE/bin/pantheon-local"
  cp "$PREFLIGHT" "$FIXTURE/packaging/release/check-preflight.sh"
  printf '0.2.4\n' > "$FIXTURE/VERSION"
  printf '# Changelog\n\n## Unreleased\n\n## 0.2.4 — 2026-10-09\n\nRelease notes.\n' > "$FIXTURE/CHANGELOG.md"
  git init -q "$FIXTURE"
  git -C "$FIXTURE" symbolic-ref HEAD refs/heads/main
  git -C "$FIXTURE" config user.name 'PLT Fixture'
  git -C "$FIXTURE" config user.email 'fixture@example.invalid'
  git -C "$FIXTURE" add .
  git -C "$FIXTURE" commit -qm 'Create isolated release fixture'
  [ -z "$(git -C "$FIXTURE" remote)" ] || fail 'fixture unexpectedly has remote'
}

head_sha() { git -C "$FIXTURE" rev-parse HEAD; }

# Read back Git identity, refs, worktree and source blobs around every call.
# A failure is allowed, but no preflight invocation may change any of them.
run_preflight() {
  local before_head before_refs before_status before_files after_head after_refs after_status after_files
  before_head=$(git -C "$FIXTURE" rev-parse HEAD 2>/dev/null || printf 'NO_HEAD')
  before_refs=$(git -C "$FIXTURE" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null || true)
  before_status=$(git -C "$FIXTURE" status --porcelain --untracked-files=all 2>/dev/null || true)
  before_files=$(git hash-object "$FIXTURE/VERSION" "$FIXTURE/CHANGELOG.md" "$FIXTURE/bin/pantheon-local" 2>/dev/null || true)

  RC=0
  OUTPUT=$(bash "$FIXTURE/packaging/release/check-preflight.sh" "$@" 2>&1) || RC=$?

  after_head=$(git -C "$FIXTURE" rev-parse HEAD 2>/dev/null || printf 'NO_HEAD')
  after_refs=$(git -C "$FIXTURE" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null || true)
  after_status=$(git -C "$FIXTURE" status --porcelain --untracked-files=all 2>/dev/null || true)
  after_files=$(git hash-object "$FIXTURE/VERSION" "$FIXTURE/CHANGELOG.md" "$FIXTURE/bin/pantheon-local" 2>/dev/null || true)
  [ "$before_head" = "$after_head" ] || fail 'preflight moved HEAD'
  [ "$before_refs" = "$after_refs" ] || fail 'preflight created or changed Git refs'
  [ "$before_status" = "$after_status" ] || fail 'preflight mutated working tree'
  [ "$before_files" = "$after_files" ] || fail 'preflight changed release source files'
}

assert_pass() {
  local label=$1
  shift
  run_preflight "$@"
  [ "$RC" -eq 0 ] || fail "$label unexpectedly failed: $OUTPUT"
  case "$OUTPUT" in
    *'LOCAL_PREFLIGHT=PASS'*'Not checked: remote Git refs, GitHub CI'*) ;;
    *) fail "$label missing success or remote-state limitation" ;;
  esac
}

assert_refuse() {
  local label=$1 expected=$2
  shift 2
  run_preflight "$@"
  [ "$RC" -ne 0 ] || fail "$label unexpectedly passed"
  case "$OUTPUT" in
    *"$expected"*) ;;
    *) fail "$label wrong failure reason: $OUTPUT" ;;
  esac
}

make_fixture clean-pretag
assert_pass 'clean pretag' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"
assert_refuse 'missing mode' 'explicit --mode' --date 2026-10-09 --expect-head "$(head_sha)"
assert_refuse 'missing date' 'explicit --date' --mode pretag --expect-head "$(head_sha)"
assert_refuse 'missing expected SHA' '--expect-head requires' --mode pretag --date 2026-10-09
assert_refuse 'short SHA' 'full lowercase' --mode pretag --date 2026-10-09 --expect-head "$(head_sha | cut -c1-8)"
assert_refuse 'invalid date format' 'YYYY-MM-DD' --mode pretag --date 2026-10-9 --expect-head "$(head_sha)"
assert_refuse 'invalid calendar month' 'invalid calendar month' --mode pretag --date 2026-13-01 --expect-head "$(head_sha)"
assert_refuse 'invalid February date' 'invalid calendar day' --mode pretag --date 2026-02-29 --expect-head "$(head_sha)"
assert_refuse 'stale expected date' 'CHANGELOG.md heading must exactly match' --mode pretag --date 2026-10-10 --expect-head "$(head_sha)"
assert_refuse 'wrong expected SHA' 'HEAD differs from --expect-head' --mode pretag --date 2026-10-09 --expect-head 0000000000000000000000000000000000000000
assert_refuse 'tag required in tagged mode' 'local annotated v0.2.4 is required' --mode tagged --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture leap-day
sed 's/2026-10-09/2028-02-29/' "$FIXTURE/CHANGELOG.md" > "$FIXTURE/CHANGELOG.md.updated"
mv "$FIXTURE/CHANGELOG.md.updated" "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add CHANGELOG.md
git -C "$FIXTURE" commit -qm 'Use leap day in isolated fixture'
assert_pass 'valid leap-day date' --mode pretag --date 2028-02-29 --expect-head "$(head_sha)"

make_fixture stale-changelog
sed 's/2026-10-09/2026-10-02/' "$FIXTURE/CHANGELOG.md" > "$FIXTURE/CHANGELOG.md.updated"
mv "$FIXTURE/CHANGELOG.md.updated" "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add CHANGELOG.md
git -C "$FIXTURE" commit -qm 'Stale changelog heading'
assert_refuse 'stale changelog' 'CHANGELOG.md heading must exactly match' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture duplicate-changelog
printf '\n## 0.2.4 — 2026-10-02\n' >> "$FIXTURE/CHANGELOG.md"
git -C "$FIXTURE" add CHANGELOG.md
git -C "$FIXTURE" commit -qm 'Duplicate changelog heading'
assert_refuse 'duplicate release heading' 'exactly one section' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture mismatched-version
printf '0.2.5\n' > "$FIXTURE/VERSION"
git -C "$FIXTURE" add VERSION
git -C "$FIXTURE" commit -qm 'Mismatched VERSION'
assert_refuse 'version changelog mismatch' 'exactly one section for 0.2.5' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture prerelease-version
printf '0.2.4-dev\n' > "$FIXTURE/VERSION"
git -C "$FIXTURE" add VERSION
git -C "$FIXTURE" commit -qm 'Reject prerelease VERSION'
assert_refuse 'prerelease cannot be a final release' 'stable MAJOR.MINOR.PATCH' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture cli-mismatch
cat > "$FIXTURE/bin/pantheon-local" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  version) printf 'pantheon-local 0.0.0\n' ;;
  --version) printf 'pantheon-local 0.2.4\n' ;;
esac
MOCK
git -C "$FIXTURE" add bin/pantheon-local
git -C "$FIXTURE" commit -qm 'Simulate invalid CLI version'
assert_refuse 'CLI version mismatch' 'CLI version output does not match VERSION' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture cli-flag-mismatch
cat > "$FIXTURE/bin/pantheon-local" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  version) printf 'pantheon-local 0.2.4\n' ;;
  --version) printf 'pantheon-local 0.0.0\n' ;;
esac
MOCK
git -C "$FIXTURE" add bin/pantheon-local
git -C "$FIXTURE" commit -qm 'Simulate invalid CLI version flag'
assert_refuse 'CLI --version mismatch' 'CLI --version output does not match VERSION' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture dirty-tracked
printf '# Changed after commit\n' >> "$FIXTURE/CHANGELOG.md"
assert_refuse 'dirty tracked checkout' 'working tree/index has changes' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture dirty-untracked
printf 'scratch\n' > "$FIXTURE/untracked-file"
assert_refuse 'dirty untracked checkout' 'working tree/index has changes' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture lightweight-tag
git -C "$FIXTURE" tag v0.2.4
assert_refuse 'local pretag collision' 'already exists' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"
assert_refuse 'lightweight release tag' 'must be an annotated Git tag' --mode tagged --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture annotated-tag
git -C "$FIXTURE" tag -a v0.2.4 -m 'PLT test annotated release'
assert_pass 'matching annotated tag' --mode tagged --date 2026-10-09 --expect-head "$(head_sha)"
assert_refuse 'annotated tag cannot be pretag' 'already exists' --mode pretag --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture tag-drift
git -C "$FIXTURE" tag -a v0.2.4 -m 'PLT test annotated release'
git -C "$FIXTURE" commit -q --allow-empty -m 'Shift HEAD after local tag'
assert_refuse 'tag points at earlier commit' 'does not resolve to the expected HEAD' --mode tagged --date 2026-10-09 --expect-head "$(head_sha)"

make_fixture non-git
rm -rf "$FIXTURE/.git"
assert_refuse 'Git checkout required' 'Git source checkout' --mode pretag --date 2026-10-09 --expect-head 0000000000000000000000000000000000000000

printf 'release preflight tests passed\n'
