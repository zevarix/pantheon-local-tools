#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

export HOME="$TMP_ROOT/home"
export PANTHEON_LOCAL_CONFIG="$TMP_ROOT/config/pantheon-local-tools/config"
MOCK_BIN="$TMP_ROOT/bin"
MOCK_DATA="$TMP_ROOT/data"
LOCAL_ROOT="$TMP_ROOT/sites"
MOCK_TERMINUS_LOG="$TMP_ROOT/terminus.log"
MOCK_PROVIDER_LOG="$TMP_ROOT/provider.log"
mkdir -p "$HOME" "$MOCK_BIN" "$MOCK_DATA"
: > "$MOCK_TERMINUS_LOG"
: > "$MOCK_PROVIDER_LOG"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "expected output not to contain [$2], got [$1]" ;; *) ;; esac; }
assert_file_not_contains() { if [ -f "$1" ] && grep -F "$2" "$1" >/dev/null 2>&1; then fail "expected $1 not to contain [$2]"; fi; }

create_remote() {
  local site=$1 tags=$2 source bare
  source="$MOCK_DATA/$site-source"
  bare="$MOCK_DATA/$site.git"
  mkdir -p "$source"
  git -C "$source" init -q
  git -C "$source" config user.name 'Test User'
  git -C "$source" config user.email 'test@example.com'
  printf '%s initial\n' "$site" > "$source/README.md"
  git -C "$source" add README.md
  git -C "$source" commit -qm 'Initial Dev commit'
  git -C "$source" branch -M master
  git clone -q --bare "$source" "$bare"
  git --git-dir="$bare" symbolic-ref HEAD refs/heads/master
  git -C "$source" remote add origin "$bare"
  printf '%s\n' "$tags" > "$MOCK_DATA/$site.tags"
  printf '%s\n' "$bare" > "$MOCK_DATA/$site.git-url"
}

advance_remote() {
  local site=$1 source
  source="$MOCK_DATA/$site-source"
  printf '%s update\n' "$site" >> "$source/README.md"
  git -C "$source" add README.md
  git -C "$source" commit -qm 'Advance Dev'
  git -C "$source" push -q origin master
}

create_remote example-site 'Example Group'
create_remote alpha-site 'Example Group'
create_remote beta-site 'Another Group'
create_remote gamma-site 'Unmapped Group'

printf '%s\n' example-site alpha-site beta-site gamma-site > "$MOCK_DATA/sites"

cat > "$MOCK_BIN/terminus" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
line='terminus'
for arg in "$@"; do line="$line|$arg"; done
printf '%s\n' "$line" >> "${MOCK_TERMINUS_LOG:?}"
case "${1:-}" in
  auth:whoami)
    printf '%s\n' 'developer@example.com'
    ;;
  site:list)
    [ "${2:-}" = '--format=list' ] || exit 2
    [ "${3:-}" = '--field=name' ] || exit 2
    cat "${MOCK_DATA:?}/sites"
    ;;
  env:list)
    site=${2:?}
    [ "${3:-}" = '--format=list' ] || exit 2
    [ "${4:-}" = '--field=id' ] || exit 2
    if [ "$site" = nodev-site ]; then printf '%s\n' test live; else printf '%s\n' dev test live; fi
    ;;
  site:info)
    site=${2:?}
    [ "${3:-}" = '--field=organization' ] || exit 2
    printf '%s\n' 'Example Org'
    ;;
  tag:list)
    site=${2:?}
    [ "${4:-}" = '--format=list' ] || exit 2
    cat "${MOCK_DATA:?}/$site.tags"
    ;;
  connection:info)
    target=${2:?}
    [ "${3:-}" = '--field=git_url' ] || exit 2
    site=${target%.dev}
    cat "${MOCK_DATA:?}/$site.git-url"
    ;;
  *)
    printf 'unexpected terminus command: %s\n' "${1:-}" >&2
    exit 2
    ;;
esac
MOCK
chmod +x "$MOCK_BIN/terminus"

for provider in ddev lando; do
  cat > "$MOCK_BIN/$provider" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$0 $*" >> "${MOCK_PROVIDER_LOG:?}"
exit 9
MOCK
  chmod +x "$MOCK_BIN/$provider"
done

export PATH="$MOCK_BIN:$PATH"
export MOCK_DATA MOCK_TERMINUS_LOG MOCK_PROVIDER_LOG

bash "$CLI" config set root "$LOCAL_ROOT"
bash "$CLI" config tag set 'Example Group' clients

help_output=$(bash "$CLI" checkout --help)
assert_contains "$help_output" 'pantheon-local checkout SITE.dev'
assert_contains "$help_output" 'pantheon-local checkout dev (--all | --tag TAG'
assert_contains "$help_output" 'pantheon-local checkout sync SITE.dev'
assert_contains "$help_output" 'CLONE'
assert_contains "$help_output" 'UPDATE'
assert_contains "$help_output" '--format default|json'

# Missing single-site checkout plans as CLONE with no local/provider/data side effects.
: > "$MOCK_PROVIDER_LOG"
dry_output=$(bash "$CLI" checkout example-site.dev --dry-run)
assert_contains "$dry_output" 'Pantheon canonical Dev checkout plan'
assert_contains "$dry_output" 'CLONE'
assert_contains "$dry_output" 'example-site'
assert_contains "$dry_output" 'destination-missing'
[ ! -e "$LOCAL_ROOT/clients/example-site" ] || fail 'dry-run created canonical checkout'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'dry-run invoked a provider'

# Default is identical to explicitly requested default format; retired spelling is rejected.
assert_eq "$(bash "$CLI" checkout example-site.dev --dry-run --format default)" "$dry_output"
set +e
bash "$CLI" checkout example-site.dev --dry-run --format human >/dev/null 2>&1
legacy_rc=$?
set -e
[ "$legacy_rc" -ne 0 ] || fail 'retired format alias was accepted'

# Structured plan is deterministic, bounded, and recordable.
json_plan=$(bash "$CLI" checkout example-site.dev --dry-run --format json)
assert_contains "$json_plan" '"schema_version":1'
assert_contains "$json_plan" '"command":"checkout"'
assert_contains "$json_plan" '"workflow":{"schema_version":1,"name":"canonical-dev-checkout","kind":"built-in","phase":"plan","status":"planned"'
assert_contains "$json_plan" '"result":{"state":"planned","reason_code":"checkout-plan-ready","exit_code":0'
assert_contains "$json_plan" '"mode":"checkout"'
assert_contains "$json_plan" '"site":"example-site"'
assert_contains "$json_plan" '"action":"CLONE"'
assert_contains "$json_plan" '"destination":'
assert_contains "$json_plan" '"pantheon":"terminus"'
RECORD="$TMP_ROOT/checkout-plan.json"
record_plan=$(bash "$CLI" checkout example-site.dev --dry-run --format json --record "$RECORD")
assert_eq "$(cat "$RECORD")" "$record_plan"
set +e
bash "$CLI" checkout example-site.dev --dry-run --record "$RECORD" >/dev/null 2>&1
record_rc=$?
set -e
assert_eq "$record_rc" '30'

# Real checkout clones transactionally and returns the stable changed category.
set +e
clone_output=$(bash "$CLI" checkout example-site.dev 2>&1)
clone_rc=$?
set -e
assert_eq "$clone_rc" '10'
assert_contains "$clone_output" 'CLONED'
DEST="$LOCAL_ROOT/clients/example-site"
[ -d "$DEST/.git" ] || fail 'canonical Dev checkout was not cloned'
assert_eq "$(git -C "$DEST" rev-parse --abbrev-ref HEAD)" master
assert_eq "$(git config --file "$DEST/.git/pantheon-local-tools/state" --get pantheon.site)" example-site
assert_eq "$(git config --file "$DEST/.git/pantheon-local-tools/state" --get pantheon.environment)" dev
assert_eq "$(git config --file "$DEST/.git/pantheon-local-tools/state" --get checkout.kind)" canonical-dev
assert_eq "$(git config --file "$DEST/.git/pantheon-local-tools/state" --get pantheon.tag)" 'Example Group'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'canonical checkout invoked a provider'

# Rerun recognizes CURRENT rather than overwriting.
current_output=$(bash "$CLI" checkout example-site.dev)
assert_contains "$current_output" 'CURRENT'
assert_contains "$current_output" 'dev-current'

# Behind checkout is only reported by normal checkout; it moves only through explicit sync.
before_sha=$(git -C "$DEST" rev-parse HEAD)
advance_remote example-site
update_plan=$(bash "$CLI" checkout example-site.dev)
assert_contains "$update_plan" 'UPDATE'
assert_eq "$(git -C "$DEST" rev-parse HEAD)" "$before_sha"
sync_dry=$(bash "$CLI" checkout sync example-site.dev --dry-run)
assert_contains "$sync_dry" 'UPDATE'
assert_eq "$(git -C "$DEST" rev-parse HEAD)" "$before_sha"
set +e
sync_output=$(bash "$CLI" checkout sync example-site.dev 2>&1)
sync_rc=$?
set -e
assert_eq "$sync_rc" '10'
assert_contains "$sync_output" 'UPDATED'
assert_eq "$(git -C "$DEST" rev-parse HEAD)" "$(git --git-dir="$MOCK_DATA/example-site.git" rev-parse HEAD)"

# Dirty worktree is preserved and classified SKIP.
printf 'dirty\n' >> "$DEST/README.md"
set +e
dirty_output=$(bash "$CLI" checkout sync example-site.dev 2>&1)
dirty_rc=$?
set -e
assert_eq "$dirty_rc" '30'
assert_contains "$dirty_output" 'SKIP'
assert_contains "$dirty_output" 'dirty-working-tree'
grep -F dirty "$DEST/README.md" >/dev/null || fail 'dirty checkout content was changed'
git -C "$DEST" checkout -q -- README.md

# Occupied non-checkout destination is never overwritten.
mkdir -p "$LOCAL_ROOT/clients/occupied-site"
printf 'keep\n' > "$LOCAL_ROOT/clients/occupied-site/file.txt"
create_remote occupied-site 'Example Group'
printf '%s\n' occupied-site >> "$MOCK_DATA/sites"
set +e
occupied_output=$(bash "$CLI" checkout occupied-site.dev 2>&1)
occupied_rc=$?
set -e
assert_eq "$occupied_rc" '30'
assert_contains "$occupied_output" 'BLOCKED'
assert_contains "$occupied_output" 'occupied-destination'
assert_eq "$(cat "$LOCAL_ROOT/clients/occupied-site/file.txt")" keep
grep -v '^occupied-site$' "$MOCK_DATA/sites" > "$MOCK_DATA/sites.next"
mv "$MOCK_DATA/sites.next" "$MOCK_DATA/sites"

# Configured routing ambiguity and no-match fail closed per site.
bash "$CLI" config tag set 'Another Group' apps
printf 'Example Group\nAnother Group\n' > "$MOCK_DATA/beta-site.tags"
set +e
ambiguous_output=$(bash "$CLI" checkout beta-site.dev --dry-run 2>&1)
ambiguous_rc=$?
set -e
assert_eq "$ambiguous_rc" '31'
assert_contains "$ambiguous_output" 'BLOCKED'
assert_contains "$ambiguous_output" 'ambiguous-tag-route'
set +e
unmapped_output=$(bash "$CLI" checkout gamma-site.dev --dry-run 2>&1)
unmapped_rc=$?
set -e
assert_eq "$unmapped_rc" '31'
assert_contains "$unmapped_output" 'unmapped-tag-route'

# Repeated Tag selectors are OR selection; result order is deterministic by site name.
printf '%s\n' 'Another Group' > "$MOCK_DATA/beta-site.tags"
multi_json=$(bash "$CLI" checkout dev --tag 'Example Group' --tag 'Another Group' --dry-run --format json)
assert_contains "$multi_json" '"site":"alpha-site"'
assert_contains "$multi_json" '"site":"beta-site"'
assert_contains "$multi_json" '"site":"example-site"'
assert_not_contains "$multi_json" '"site":"gamma-site"'
case "$multi_json" in
  *'"site":"alpha-site"'*'"site":"beta-site"'*'"site":"example-site"'*) ;;
  *) fail 'estate results were not deterministically ordered' ;;
esac

# A single Tag selects only sites carrying that configured route.
tag_json=$(bash "$CLI" checkout dev --tag 'Another Group' --dry-run --format json)
assert_contains "$tag_json" '"site":"beta-site"'
assert_not_contains "$tag_json" '"site":"alpha-site"'
assert_not_contains "$tag_json" '"site":"gamma-site"'

# Safe rerun/resume: one selected site can already be complete while another remains missing.
set +e
alpha_output=$(bash "$CLI" checkout alpha-site.dev 2>&1)
alpha_rc=$?
set -e
assert_eq "$alpha_rc" '10'
assert_contains "$alpha_output" 'CLONED'
set +e
resume_output=$(bash "$CLI" checkout dev --tag 'Example Group' 2>&1)
resume_rc=$?
set -e
assert_eq "$resume_rc" '0'
assert_contains "$resume_output" 'CURRENT'
assert_contains "$resume_output" 'example-site'
assert_contains "$resume_output" 'alpha-site'

# --all includes unmapped sites and reports routing blockers without guessing.
set +e
all_json=$(bash "$CLI" checkout dev --all --dry-run --format json 2>&1)
all_rc=$?
set -e
assert_eq "$all_rc" '31'
assert_contains "$all_json" '"site":"gamma-site"'
assert_contains "$all_json" '"reason_code":"unmapped-tag-route"'

# Real --all execution completes safe sites and preserves blocked sites; rerun is idempotent.
set +e
all_run=$(bash "$CLI" checkout dev --all 2>&1)
all_run_rc=$?
set -e
assert_eq "$all_run_rc" '31'
assert_contains "$all_run" 'CLONED'
assert_contains "$all_run" 'beta-site'
assert_contains "$all_run" 'BLOCKED'
assert_contains "$all_run" 'gamma-site'
[ -d "$LOCAL_ROOT/apps/beta-site/.git" ] || fail 'safe --all execution did not clone beta-site'
set +e
all_rerun=$(bash "$CLI" checkout dev --all 2>&1)
all_rerun_rc=$?
set -e
assert_eq "$all_rerun_rc" '31'
assert_contains "$all_rerun" 'CURRENT'
assert_contains "$all_rerun" 'beta-site'
assert_contains "$all_rerun" 'BLOCKED'
assert_contains "$all_rerun" 'gamma-site'

# Sync mode never creates a missing checkout.
rm -rf "$LOCAL_ROOT/apps/beta-site"
set +e
sync_missing=$(bash "$CLI" checkout sync beta-site.dev --dry-run 2>&1)
sync_missing_rc=$?
set -e
assert_eq "$sync_missing_rc" '30'
assert_contains "$sync_missing" 'SKIP'
assert_contains "$sync_missing" 'missing-checkout'
[ ! -e "$LOCAL_ROOT/apps/beta-site" ] || fail 'sync created a missing checkout'

# Tag-selected estate sync fast-forwards every safe behind checkout sequentially.
advance_remote alpha-site
advance_remote example-site
set +e
tag_sync_output=$(bash "$CLI" checkout sync --tag 'Example Group' 2>&1)
tag_sync_rc=$?
set -e
assert_eq "$tag_sync_rc" '10'
assert_contains "$tag_sync_output" 'UPDATED'
assert_contains "$tag_sync_output" 'alpha-site'
assert_contains "$tag_sync_output" 'example-site'
assert_eq "$(git -C "$LOCAL_ROOT/clients/alpha-site" rev-parse HEAD)" "$(git --git-dir="$MOCK_DATA/alpha-site.git" rev-parse HEAD)"
assert_eq "$(git -C "$LOCAL_ROOT/clients/example-site" rev-parse HEAD)" "$(git --git-dir="$MOCK_DATA/example-site.git" rev-parse HEAD)"

# No provider/data/runtime commands were ever invoked by checkout/sync.
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'checkout workflow invoked a provider runtime'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:create'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'env:clone-content'

printf 'checkout tests passed\n'
