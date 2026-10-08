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
  printf 'name: %s\nrecipe: pantheon\n' "$site" > "$source/.lando.yml"
  git -C "$source" add README.md .lando.yml
  git -C "$source" commit -qm 'Initial Dev commit'
  git -C "$source" branch -M master
  git clone -q --bare "$source" "$bare"
  git --git-dir="$bare" symbolic-ref HEAD refs/heads/master
  git -C "$source" remote add origin "$bare"
  printf '%s\n' "$tags" > "$MOCK_DATA/$site.tags"
  printf '%s\n' "$bare" > "$MOCK_DATA/$site.git-url"
  printf '%040d\n' 11 > "$MOCK_DATA/$site.test-hash"
  printf '%040d\n' 22 > "$MOCK_DATA/$site.live-hash"
}

advance_remote() {
  local site=$1 source
  source="$MOCK_DATA/$site-source"
  printf '%s remote update\n' "$site" >> "$source/README.md"
  git -C "$source" add README.md
  git -C "$source" commit -qm 'Advance Dev'
  git -C "$source" push -q origin master
}

for site in current-site behind-site ahead-site diverged-site dirty-site missing-site; do
  case "$site" in diverged-site|dirty-site) tags='Another Group' ;; *) tags='Example Group' ;; esac
  create_remote "$site" "$tags"
done
create_remote ambiguous-site $'Example Group\nAnother Group'
create_remote unavailable-site 'Example Group'
printf '%s\n' current-site behind-site ahead-site diverged-site dirty-site missing-site > "$MOCK_DATA/sites"

cat > "$MOCK_BIN/terminus" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
line='terminus'
for arg in "$@"; do line="$line|$arg"; done
printf '%s\n' "$line" >> "${MOCK_TERMINUS_LOG:?}"
case "${1:-}" in
  auth:whoami) printf '%s\n' 'developer@example.com' ;;
  site:list)
    [ "${2:-}" = '--format=list' ] || exit 2
    [ "${3:-}" = '--field=name' ] || exit 2
    cat "${MOCK_DATA:?}/sites"
    ;;
  env:list)
    site=${2:?}
    [ "$site" != unavailable-site ] || exit 9
    [ "${3:-}" = '--format=list' ] || exit 2
    [ "${4:-}" = '--field=id' ] || exit 2
    printf '%s\n' dev test live
    ;;
  site:info)
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
  env:code-log)
    target=${2:?}
    [ "${3:-}" = '--format=list' ] || exit 2
    [ "${4:-}" = '--field=hash' ] || exit 2
    site=${target%.*}
    env=${target##*.}
    case "$env" in
      dev) git --git-dir="${MOCK_DATA:?}/$site.git" rev-parse HEAD ;;
      test|live) cat "${MOCK_DATA:?}/$site.$env-hash" ;;
      *) exit 2 ;;
    esac
    ;;
  *) printf 'unexpected terminus command: %s\n' "${1:-}" >&2; exit 2 ;;
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
bash "$CLI" config tag set 'Another Group' apps

clone_local() {
  local site=$1 route=$2 dest
  dest="$LOCAL_ROOT/$route/$site"
  mkdir -p "${dest%/*}"
  git clone -q "$MOCK_DATA/$site.git" "$dest"
  git -C "$dest" config user.name 'Test User'
  git -C "$dest" config user.email 'test@example.com'
  printf '%s\n' "$dest"
}

CURRENT=$(clone_local current-site clients)
BEHIND=$(clone_local behind-site clients)
AHEAD=$(clone_local ahead-site clients)
DIVERGED=$(clone_local diverged-site apps)
DIRTY=$(clone_local dirty-site apps)

# Provider source coverage: detected on current; recorded ddev on behind.
mkdir -p "$BEHIND/.git/pantheon-local-tools"
git config --file "$BEHIND/.git/pantheon-local-tools/state" local.provider ddev

advance_remote behind-site
printf 'local ahead\n' >> "$AHEAD/README.md"
git -C "$AHEAD" add README.md
git -C "$AHEAD" commit -qm 'Local ahead commit'
printf 'local diverged\n' >> "$DIVERGED/README.md"
git -C "$DIVERGED" add README.md
git -C "$DIVERGED" commit -qm 'Local divergent commit'
advance_remote diverged-site
printf 'dirty\n' >> "$DIRTY/README.md"

# Capture local state to prove inspection does not mutate it.
current_head=$(git -C "$CURRENT" rev-parse HEAD)
behind_head=$(git -C "$BEHIND" rev-parse HEAD)
ahead_head=$(git -C "$AHEAD" rev-parse HEAD)
diverged_head=$(git -C "$DIVERGED" rev-parse HEAD)
dirty_status=$(git -C "$DIRTY" status --porcelain)

help_output=$(bash "$CLI" estate status --help)
assert_contains "$help_output" 'pantheon-local estate status SITE'
assert_contains "$help_output" 'pantheon-local estate status --all'
assert_contains "$help_output" '--format default|json'
assert_contains "$help_output" 'Dev/Test/Live code identities'

# Tag-selected complete inspection reports drift as information, not failure.
example_output=$(bash "$CLI" estate status --tag 'Example Group')
assert_contains "$example_output" 'Pantheon estate status'
assert_contains "$example_output" 'current-site'
assert_contains "$example_output" 'behind-site'
assert_contains "$example_output" 'ahead-site'
assert_contains "$example_output" 'missing-site'
assert_not_contains "$example_output" 'diverged-site'
assert_contains "$example_output" 'current'
assert_contains "$example_output" 'behind'
assert_contains "$example_output" 'ahead'
assert_contains "$example_output" 'missing'
assert_contains "$example_output" 'lando'
assert_contains "$example_output" 'ddev'

# Structured output preserves full code identities and complete-review semantics.
json=$(bash "$CLI" estate status --tag 'Example Group' --format json)
assert_contains "$json" '"command":"estate-status"'
assert_contains "$json" '"result":{"state":"complete","reason_code":"estate-review-needed","exit_code":0'
assert_contains "$json" '"site":"current-site","assessment":"current"'
assert_contains "$json" '"site":"behind-site","assessment":"behind"'
assert_contains "$json" '"site":"ahead-site","assessment":"ahead"'
assert_contains "$json" '"site":"missing-site","assessment":"missing"'
assert_contains "$json" '"local":{"present":true,"destination_state":"checkout"'
assert_contains "$json" '"site":"missing-site","assessment":"missing"'
assert_contains "$json" '"present":false,"destination_state":"missing"'
assert_contains "$json" '"provider":"lando","provider_source":"detected"'
assert_contains "$json" '"provider":"ddev","provider_source":"recorded"'
assert_contains "$json" '"remote_git":{"branch":"master","sha":'
assert_contains "$json" '"code":{"dev":{"status":"available","sha":'
assert_contains "$json" '"test":{"status":"available","sha":"0000000000000000000000000000000000000011"}'
assert_contains "$json" '"live":{"status":"available","sha":"0000000000000000000000000000000000000022"}'

# Other relation states remain successful inspection results.
other_json=$(bash "$CLI" estate status --tag 'Another Group' --format json)
assert_contains "$other_json" '"site":"diverged-site","assessment":"diverged"'
assert_contains "$other_json" '"site":"dirty-site","assessment":"dirty"'
assert_contains "$other_json" '"exit_code":0'

# Default is equivalent to omitted format; retired spelling remains rejected.
assert_eq "$(bash "$CLI" estate status current-site --format default)" "$(bash "$CLI" estate status current-site)"
set +e
bash "$CLI" estate status current-site --format human >/dev/null 2>&1
legacy_rc=$?
set -e
assert_eq "$legacy_rc" '64'

# Record publication matches JSON stdout and refuses overwrite.
RECORD="$TMP_ROOT/estate.json"
record_json=$(bash "$CLI" estate status current-site --format json --record "$RECORD")
assert_eq "$(cat "$RECORD")" "$record_json"
set +e
bash "$CLI" estate status current-site --record "$RECORD" >/dev/null 2>&1
record_rc=$?
set -e
assert_eq "$record_rc" '30'

# Ambiguous routing is an incomplete inspection with stable exit category.
set +e
ambiguous_json=$(bash "$CLI" estate status ambiguous-site --format json 2>&1)
ambiguous_rc=$?
set -e
assert_eq "$ambiguous_rc" '31'
assert_contains "$ambiguous_json" '"reason_code":"ambiguous-tag-route"'
assert_contains "$ambiguous_json" '"exit_category":"ambiguous-configuration"'

bash "$CLI" config tag prefer set 'Another Group' 'Example Group'
preferred_json=$(bash "$CLI" estate status ambiguous-site --format json)
assert_contains "$preferred_json" '"route":{"status":"resolved","tag":"Another Group"'
assert_contains "$preferred_json" '/apps/ambiguous-site'
assert_not_contains "$preferred_json" '"reason_code":"ambiguous-tag-route"'

# Unavailable Pantheon authority is distinct from ordinary drift.
set +e
unavailable_json=$(bash "$CLI" estate status unavailable-site --format json 2>&1)
unavailable_rc=$?
set -e
assert_eq "$unavailable_rc" '32'
assert_contains "$unavailable_json" '"assessment":"unavailable"'
assert_contains "$unavailable_json" '"failure_source":"terminus"'
assert_contains "$unavailable_json" '"exit_category":"authority-unavailable"'

# --all is deterministic and includes missing/drift states.
all_json=$(bash "$CLI" estate status --all --format json)
case "$all_json" in
  *'"site":"ahead-site"'*'"site":"behind-site"'*'"site":"current-site"'*'"site":"dirty-site"'*'"site":"diverged-site"'*'"site":"missing-site"'*) ;;
  *) fail 'estate status results were not deterministically ordered' ;;
esac

# Selection grammar stays aligned with checkout.
set +e
bash "$CLI" estate status --all --tag 'Example Group' >/dev/null 2>&1
mixed_rc=$?
set -e
assert_eq "$mixed_rc" '64'

# Inspection did not mutate local Git or invoke providers/Pantheon mutations.
assert_eq "$(git -C "$CURRENT" rev-parse HEAD)" "$current_head"
assert_eq "$(git -C "$BEHIND" rev-parse HEAD)" "$behind_head"
assert_eq "$(git -C "$AHEAD" rev-parse HEAD)" "$ahead_head"
assert_eq "$(git -C "$DIVERGED" rev-parse HEAD)" "$diverged_head"
assert_eq "$(git -C "$DIRTY" status --porcelain)" "$dirty_status"
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'estate status invoked a provider'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'env:deploy'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'env:clone-content'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:create'

printf 'estate status tests passed\n'
