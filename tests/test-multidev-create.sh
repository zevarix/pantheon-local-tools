#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

export HOME="$TMP_ROOT/home"
export PANTHEON_LOCAL_CONFIG="$TMP_ROOT/config/pantheon-local-tools/config"
MOCK_BIN="$TMP_ROOT/bin"
LOCAL_ROOT="$TMP_ROOT/sites"
SOURCE_REPO="$TMP_ROOT/source"
BROKEN_REPO="$TMP_ROOT/broken-source"
MOCK_ENVS_FILE="$TMP_ROOT/environments"
MOCK_TERMINUS_LOG="$TMP_ROOT/terminus.log"
MOCK_START_LOG="$TMP_ROOT/start.log"
MOCK_INFO_LOG="$TMP_ROOT/info.log"
mkdir -p "$HOME" "$MOCK_BIN"
printf '%s\n' dev test live > "$MOCK_ENVS_FILE"
: > "$MOCK_TERMINUS_LOG"
: > "$MOCK_START_LOG"
: > "$MOCK_INFO_LOG"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }
assert_file_contains() { grep -F "$2" "$1" >/dev/null 2>&1 || fail "expected $1 to contain [$2]"; }
assert_file_not_contains() { if grep -F "$2" "$1" >/dev/null 2>&1; then fail "expected $1 not to contain [$2]"; fi; }
assert_env_present() { grep -Fx "$1" "$MOCK_ENVS_FILE" >/dev/null 2>&1 || fail "expected remote environment [$1]"; }
assert_env_absent() { if grep -Fx "$1" "$MOCK_ENVS_FILE" >/dev/null 2>&1; then fail "unexpected remote environment [$1]"; fi; }

create_source_repo() {
  local path=$1 with_providers=$2
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name 'Test User'
  git -C "$path" config user.email 'test@example.com'
  printf 'fixture\n' > "$path/README.md"
  if [ "$with_providers" = true ]; then
    cat > "$path/.lando.yml" <<'YAML'
name: example-site
recipe: pantheon
YAML
    mkdir -p "$path/.ddev"
    cat > "$path/.ddev/config.yaml" <<'YAML'
name: example-site
type: drupal11
YAML
  fi
  git -C "$path" add .
  git -C "$path" commit -qm 'Create remote Git fixture'
}

create_source_repo "$SOURCE_REPO" true
create_source_repo "$BROKEN_REPO" false

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
  env:list)
    [ "${3:-}" = '--format=list' ] || { printf 'unexpected env:list format\n' >&2; exit 2; }
    [ "${4:-}" = '--field=id' ] || { printf 'unexpected env:list field\n' >&2; exit 2; }
    cat "${MOCK_ENVS_FILE:?}"
    ;;
  multidev:create)
    [ "${4:-}" = '--yes' ] || { printf 'multidev:create must receive --yes\n' >&2; exit 2; }
    [ "${MOCK_CREATE_FAIL:-false}" != true ] || exit 9
    new_env=${3:?}
    if ! git -C "${MOCK_GIT_URL:?}" show-ref --verify --quiet "refs/heads/$new_env"; then
      git -C "$MOCK_GIT_URL" branch "$new_env"
    fi
    if [ "${MOCK_VERIFY_MISSING:-false}" != true ]; then
      grep -Fx "$new_env" "$MOCK_ENVS_FILE" >/dev/null 2>&1 || printf '%s\n' "$new_env" >> "$MOCK_ENVS_FILE"
    fi
    printf 'Created %s\n' "$new_env"
    ;;
  connection:info)
    [ "${3:-}" = '--field=git_url' ] || { printf 'unexpected connection:info arguments\n' >&2; exit 2; }
    printf '%s\n' "${MOCK_GIT_URL:?}"
    ;;
  site:info)
    case "${3:-}" in
      --field=organization) printf '%s\n' 'Example Org' ;;
      --field=framework) printf '%s\n' 'drupal11' ;;
      *) printf 'unexpected site:info arguments\n' >&2; exit 2 ;;
    esac
    ;;
  tag:list)
    printf '%s\n' 'Generic Tag'
    ;;
  *)
    printf 'unexpected terminus command: %s\n' "${1:-}" >&2
    exit 2
    ;;
esac
MOCK
chmod +x "$MOCK_BIN/terminus"

cat > "$MOCK_BIN/lando" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  start)
    printf '%s\n' "$PWD" >> "${MOCK_START_LOG:?}"
    ;;
  info)
    printf '%s\n' "$PWD" >> "${MOCK_INFO_LOG:?}"
    printf '%s\n' '["https://example-runtime.test/"]'
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$MOCK_BIN/lando"

cat > "$MOCK_BIN/ddev" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  start)
    printf '%s\n' "$PWD" >> "${MOCK_START_LOG:?}"
    ;;
  describe)
    [ "${2:-}" = -j ] || exit 2
    printf '%s\n' "$PWD" >> "${MOCK_INFO_LOG:?}"
    printf '%s\n' '{"raw":{"primary_url":"https://example-ddev.test"}}'
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$MOCK_BIN/ddev"

export PATH="$MOCK_BIN:$PATH"
export MOCK_ENVS_FILE MOCK_TERMINUS_LOG MOCK_START_LOG MOCK_INFO_LOG
export MOCK_GIT_URL="$SOURCE_REPO"

bash "$CLI" config set root "$LOCAL_ROOT"
bash "$CLI" config set provider lando

help_output=$(bash "$CLI" multidev create --help)
assert_contains "$help_output" 'THIS COMMAND PERFORMS AN EXPLICIT REMOTE PANTHEON WRITE'
assert_contains "$help_output" 'at most 11 characters'
assert_contains "$help_output" '--yes'
assert_contains "$help_output" 'If remote creation succeeds but local checkout/start fails'
assert_contains "$help_output" 'Multidev is deliberately preserved.'

# Dry-run validates remote/local inputs but performs neither remote creation nor local checkout.
: > "$MOCK_TERMINUS_LOG"
dry_output=$(bash "$CLI" multidev create example-site.live feature1 --provider lando --group migration --dry-run)
assert_contains "$dry_output" 'Pantheon Local Tools Multidev creation plan'
assert_contains "$dry_output" 'Source environment:    example-site.live'
assert_contains "$dry_output" 'New environment:       example-site.feature1'
assert_contains "$dry_output" 'Remote content clone:  database and files (Terminus default)'
assert_contains "$dry_output" 'Remote mutation:       not performed (--dry-run)'
assert_contains "$dry_output" 'Local checkout:        not performed (--dry-run)'
assert_env_absent feature1
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:create'
[ ! -e "$LOCAL_ROOT/multidev/migration/example-site-feature1" ] || fail 'dry-run created a local checkout'

# Source must exist and target must not already exist before any mutation.
: > "$MOCK_TERMINUS_LOG"
if bash "$CLI" multidev create example-site.missing sourcebad --yes >/dev/null 2>&1; then
  fail 'missing source environment was accepted'
fi
assert_env_absent sourcebad
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:create'
printf '%s\n' existing >> "$MOCK_ENVS_FILE"
: > "$MOCK_TERMINUS_LOG"
if bash "$CLI" multidev create example-site.live existing --yes >/dev/null 2>&1; then
  fail 'existing target environment was accepted'
fi
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:create'

# Pantheon Multidev naming rules are enforced locally before contacting Terminus.
for invalid in Upper bad_name toolongname12 master; do
  : > "$MOCK_TERMINUS_LOG"
  if bash "$CLI" multidev create example-site.live "$invalid" --yes >/dev/null 2>&1; then
    fail "invalid Multidev name was accepted: $invalid"
  fi
  [ ! -s "$MOCK_TERMINUS_LOG" ] || fail "invalid name contacted Terminus: $invalid"
done

# Non-interactive real creation requires the explicit PLT --yes acknowledgement.
: > "$MOCK_TERMINUS_LOG"
if bash "$CLI" multidev create example-site.live noack --provider lando >/dev/null 2>&1; then
  fail 'non-interactive creation succeeded without --yes'
fi
assert_env_absent noack
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:create'

# Successful creation is verified, then handed to the existing transactional checkout path.
: > "$MOCK_TERMINUS_LOG"
success_output=$(bash "$CLI" multidev create example-site.live feature1 --provider lando --group migration --yes)
assert_contains "$success_output" 'Confirmation:          acknowledged by --yes'
assert_contains "$success_output" 'Remote Multidev verified: example-site.feature1'
assert_contains "$success_output" 'Handing off to existing local Multidev checkout path...'
assert_contains "$success_output" 'Created Pantheon multidev checkout'
assert_contains "$success_output" 'Remote creation and local Multidev handoff completed for example-site.feature1.'
assert_env_present feature1
assert_file_contains "$MOCK_TERMINUS_LOG" 'terminus|multidev:create|example-site.live|feature1|--yes'
SUCCESS_DEST="$LOCAL_ROOT/multidev/migration/example-site-feature1"
[ -d "$SUCCESS_DEST/.git" ] || fail 'successful remote creation did not produce local checkout'
[ -f "$SUCCESS_DEST/.lando.local.yml" ] || fail 'existing Lando checkout path did not create local override'
[ ! -f "$SUCCESS_DEST/.ddev/config.local.yaml" ] || fail 'wrong provider override was created'
[ "$(git config --file "$SUCCESS_DEST/.git/pantheon-local-tools/state" --get pantheon.environment)" = feature1 ] || fail 'checkout state did not record new environment'

# Existing --start semantics are passed through only after successful checkout finalization.
: > "$MOCK_START_LOG"
start_output=$(bash "$CLI" multidev create example-site.live feature2 --provider lando --start --yes)
assert_contains "$start_output" 'Remote Multidev verified: example-site.feature2'
START_DEST="$LOCAL_ROOT/multidev/example-site-feature2"
assert_file_contains "$MOCK_START_LOG" "$START_DEST"
assert_env_present feature2

# DDEV provider choice is passed through to the existing checkout path.
ddev_output=$(bash "$CLI" multidev create example-site.live feature3 --provider ddev --yes)
assert_contains "$ddev_output" 'Provider:    ddev'
DDEV_DEST="$LOCAL_ROOT/multidev/example-site-feature3"
[ -f "$DDEV_DEST/.ddev/config.local.yaml" ] || fail 'DDEV local handoff did not use existing provider path'
assert_env_present feature3

# Terminus creation failure does not trigger local checkout or automatic deletion/retry.
export MOCK_CREATE_FAIL=true
: > "$MOCK_TERMINUS_LOG"
set +e
create_fail_output=$(bash "$CLI" multidev create example-site.live feature4 --provider lando --yes 2>&1)
create_fail_status=$?
set -e
[ "$create_fail_status" -ne 0 ] || fail 'simulated Terminus creation failure succeeded'
assert_contains "$create_fail_output" 'remote state may be partial or uncertain'
assert_env_absent feature4
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:delete'
[ ! -e "$LOCAL_ROOT/multidev/example-site-feature4" ] || fail 'creation failure produced local checkout'
unset MOCK_CREATE_FAIL

# A successful create whose verification is inconclusive does not proceed locally or recreate/delete blindly.
export MOCK_VERIFY_MISSING=true
: > "$MOCK_TERMINUS_LOG"
set +e
verify_output=$(bash "$CLI" multidev create example-site.live feature5 --provider lando --yes 2>&1)
verify_status=$?
set -e
[ "$verify_status" -ne 0 ] || fail 'missing post-create verification unexpectedly succeeded'
assert_contains "$verify_output" 'Remote state is uncertain; do not recreate blindly.'
assert_env_absent feature5
assert_file_contains "$MOCK_TERMINUS_LOG" 'terminus|multidev:create|example-site.live|feature5|--yes'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:delete'
[ ! -e "$LOCAL_ROOT/multidev/example-site-feature5" ] || fail 'unverified remote creation proceeded to local checkout'
unset MOCK_VERIFY_MISSING

# Remote success followed by local provider failure preserves the remote environment and reports a retry command.
export MOCK_GIT_URL="$BROKEN_REPO"
: > "$MOCK_TERMINUS_LOG"
set +e
handoff_output=$(bash "$CLI" multidev create example-site.live feature6 --provider lando --group retry --yes 2>&1)
handoff_status=$?
set -e
[ "$handoff_status" -ne 0 ] || fail 'broken local provider fixture unexpectedly succeeded'
assert_env_present feature6
assert_contains "$handoff_output" 'remote Multidev example-site.feature6 was created successfully, but local checkout/start failed'
assert_contains "$handoff_output" 'pantheon-local multidev example-site.feature6 --provider lando --group retry'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:delete'
[ ! -e "$LOCAL_ROOT/multidev/retry/example-site-feature6" ] || fail 'failed local handoff left a finalized checkout'

# Creation does not change the clone-only command contract: a missing existing target still fails rather than being created.
export MOCK_GIT_URL="$SOURCE_REPO"
: > "$MOCK_TERMINUS_LOG"
if bash "$CLI" multidev example-site.nevermade --provider lando >/dev/null 2>&1; then
  fail 'clone-only multidev command accepted a missing remote target'
fi
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:create'

printf 'multidev create tests passed\n'
