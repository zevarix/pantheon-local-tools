#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
MOCK_BIN="$TMP_ROOT/bin"
MOCK_LOG="$TMP_ROOT/provider.log"
mkdir -p "$MOCK_BIN"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "expected output not to contain [$2], got [$1]" ;; *) ;; esac; }
assert_file_contains() { grep -F "$2" "$1" >/dev/null 2>&1 || fail "expected $1 to contain [$2]"; }
assert_file_not_contains() { if [ -f "$1" ] && grep -F "$2" "$1" >/dev/null 2>&1; then fail "expected $1 not to contain [$2]"; fi; }

cat > "$MOCK_BIN/provider-mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
provider=$(basename "$0")
line=$provider
for arg in "$@"; do line="$line|$arg"; done
printf '%s\n' "$line" >> "${MOCK_LOG:?}"

case "$line" in
  "$provider|drush|core:status|--field=config-sync")
    printf '%s\n' "${MOCK_RUNTIME_CONFIG_PATH:?}"
    ;;
  "$provider|drush|config:status|--format=list")
    [ -z "${MOCK_CONFIG_STATUS:-}" ] || printf '%s\n' "$MOCK_CONFIG_STATUS"
    ;;
  "$provider|drush|pm:list|--type=module|--status=enabled|--field=name")
    [ "${MOCK_PM_FAIL:-false}" != true ] || exit 10
    printf '%s\n' "${MOCK_MODULES:-node}"
    ;;
  "$provider|drush|config:export|-y")
    case "${MOCK_EXPORT_MODE:-success}" in
      success)
        printf 'exported: true\n' >> "${MOCK_EXPORT_PATH:?}/system.site.yml"
        printf 'created: true\n' > "${MOCK_EXPORT_PATH:?}/created.yml"
        rm -f "${MOCK_EXPORT_PATH:?}/obsolete.yml"
        ;;
      nochange)
        ;;
      fail-partial)
        printf 'partial: true\n' >> "${MOCK_EXPORT_PATH:?}/system.site.yml"
        exit 9
        ;;
      *) exit 11 ;;
    esac
    ;;
esac
MOCK
chmod +x "$MOCK_BIN/provider-mock"
ln -s provider-mock "$MOCK_BIN/lando"
ln -s provider-mock "$MOCK_BIN/ddev"

export PATH="$MOCK_BIN:$PATH"
export MOCK_LOG
export PANTHEON_LOCAL_CONFIG="$TMP_ROOT/plt-config"

reset_mocks() {
  : > "$MOCK_LOG"
  unset MOCK_CONFIG_STATUS MOCK_MODULES MOCK_PM_FAIL MOCK_EXPORT_MODE MOCK_EXPORT_PATH MOCK_RUNTIME_CONFIG_PATH || true
}

create_repo() {
  local path=$1 provider=$2 tag=$3 strategy=$4 config_path=$5 directory
  mkdir -p "$path/$config_path"
  git -C "$path" init -q
  git -C "$path" config user.name 'Test User'
  git -C "$path" config user.email 'test@example.com'
  printf 'fixture\n' > "$path/README.md"
  printf 'uuid: fixture\n' > "$path/$config_path/system.site.yml"
  printf 'obsolete: true\n' > "$path/$config_path/obsolete.yml"

  case "$provider" in
    lando) printf 'name: example-site\nrecipe: pantheon\n' > "$path/.lando.yml" ;;
    ddev)
      mkdir -p "$path/.ddev"
      printf 'name: example-site\ntype: drupal11\n' > "$path/.ddev/config.yaml"
      ;;
    *) fail "unknown provider fixture: $provider" ;;
  esac

  git -C "$path" add .
  git -C "$path" commit -qm 'Create config export fixture'
  mkdir -p "$path/.git/pantheon-local-tools"
  git config --file "$path/.git/pantheon-local-tools/state" pantheon.tag "$tag"
  git config --file "$path/.git/pantheon-local-tools/state" local.provider "$provider"

  directory=$(basename "$path")
  bash "$CLI" config tag set "$tag" "$directory"
  bash "$CLI" config tag profile set "$tag" config-strategy "$strategy"
  bash "$CLI" config tag profile set "$tag" config-path "$config_path"
}

capture_failure() {
  local repo=$1
  shift
  local output status
  set +e
  output=$(cd "$repo" && bash "$CLI" config export "$@" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "expected config export to fail for $repo"
  printf '%s\n' "$output"
}

export_help=$(bash "$CLI" config export --help)
assert_contains "$export_help" 'pantheon-local config export [--provider ddev|lando] [--yes]'
assert_contains "$export_help" 'THIS COMMAND MUTATES PROJECT CONFIGURATION FILES.'
assert_contains "$export_help" 'full-export'
assert_contains "$export_help" 'overlay-delta  Unsupported.'
assert_contains "$export_help" 'configured export path to have no pre-existing Git changes'
assert_contains "$export_help" 'Config Ignore'
assert_contains "$export_help" 'never commits or pushes'
assert_contains "$export_help" 'Required for non-interactive use.'

# A deliberate full-export mutation succeeds, preserves unrelated dirty work,
# leaves HEAD/index untouched, and reports the exact config-path change classes.
SUCCESS="$TMP_ROOT/export-success"
create_repo "$SUCCESS" lando 'Full Export Mutation' full-export config/project-export
printf 'unrelated local notes\n' > "$SUCCESS/notes.txt"
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/project-export'
export MOCK_CONFIG_STATUS='system.site'
export MOCK_EXPORT_PATH="$SUCCESS/config/project-export"
export MOCK_EXPORT_MODE=success
head_before=$(git -C "$SUCCESS" rev-parse HEAD)
success_output=$(cd "$SUCCESS" && bash "$CLI" config export --yes)
head_after=$(git -C "$SUCCESS" rev-parse HEAD)
[ "$head_after" = "$head_before" ] || fail 'config export changed Git HEAD'
git -C "$SUCCESS" diff --cached --quiet || fail 'config export staged files unexpectedly'
assert_contains "$success_output" 'Pantheon Local Tools config export preflight'
assert_contains "$success_output" 'Drupal configuration:  differences detected'
assert_contains "$success_output" 'Export mutation plan'
assert_contains "$success_output" 'Config strategy:       full-export'
assert_contains "$success_output" 'Config Ignore module:  disabled'
assert_contains "$success_output" 'Mutation:              provider-owned drush config:export -y'
assert_contains "$success_output" 'Confirmation:          acknowledged by --yes'
assert_contains "$success_output" 'Export change summary for config/project-export:'
assert_contains "$success_output" 'created: 1'
assert_contains "$success_output" 'changed: 1'
assert_contains "$success_output" 'deleted: 1'
assert_contains "$success_output" 'Final Git status:'
assert_contains "$success_output" 'notes.txt'
assert_contains "$success_output" 'Configuration export completed.'
assert_file_contains "$MOCK_LOG" 'lando|drush|config:export|-y'
assert_file_not_contains "$MOCK_LOG" '--commit'
assert_file_not_contains "$MOCK_LOG" '--add'

# Existing Git changes inside the configured export path fail before any provider call.
DIRTY_PATH="$TMP_ROOT/dirty-path"
create_repo "$DIRTY_PATH" lando 'Dirty Export Path' full-export config/dirty-export
printf 'manual: change\n' >> "$DIRTY_PATH/config/dirty-export/system.site.yml"
reset_mocks
dirty_output=$(capture_failure "$DIRTY_PATH" --yes)
assert_contains "$dirty_output" 'configured export path has pre-existing Git changes'
[ ! -s "$MOCK_LOG" ] || fail 'dirty export path invoked provider commands'

# Overlay export is categorically unsupported and fails before provider resolution/invocation.
OVERLAY="$TMP_ROOT/overlay"
create_repo "$OVERLAY" lando 'Protected Overlay Export' overlay-delta config/site-overrides
reset_mocks
overlay_output=$(capture_failure "$OVERLAY" --yes)
assert_contains "$overlay_output" 'overlay-delta config export is unsupported'
assert_contains "$overlay_output" 'protected partial override set'
[ ! -s "$MOCK_LOG" ] || fail 'overlay config export invoked provider commands'

# Invalid provider syntax fails at the public boundary before provider calls.
INVALID_PROVIDER="$TMP_ROOT/invalid-provider"
create_repo "$INVALID_PROVIDER" lando 'Invalid Provider Export' full-export config/export
reset_mocks
invalid_provider_output=$(capture_failure "$INVALID_PROVIDER" --provider other --yes)
assert_contains "$invalid_provider_output" '--provider must be ddev or lando'
[ ! -s "$MOCK_LOG" ] || fail 'invalid provider export invoked provider commands'

# Non-interactive use requires explicit --yes and never reaches cex without it.
CONFIRM="$TMP_ROOT/confirmation"
create_repo "$CONFIRM" lando 'Confirmation Export' full-export config/export
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/export'
export MOCK_CONFIG_STATUS='system.site'
export MOCK_EXPORT_PATH="$CONFIRM/config/export"
export MOCK_EXPORT_MODE=nochange
confirm_output=$(capture_failure "$CONFIRM")
assert_contains "$confirm_output" 'non-interactive config export requires --yes acknowledgement'
assert_file_not_contains "$MOCK_LOG" 'config:export'

# Enabled Config Ignore is reported, but its runtime export rules remain Drupal authority.
IGNORE="$TMP_ROOT/config-ignore"
create_repo "$IGNORE" lando 'Config Ignore Export' full-export config/export
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/export'
export MOCK_CONFIG_STATUS='system.site'
export MOCK_MODULES=$'node\nconfig_ignore'
export MOCK_EXPORT_PATH="$IGNORE/config/export"
export MOCK_EXPORT_MODE=nochange
ignore_output=$(cd "$IGNORE" && bash "$CLI" config export --yes)
assert_contains "$ignore_output" 'Config Ignore module:  enabled'
assert_contains "$ignore_output" 'runtime export rules'
assert_contains "$ignore_output" 'PLT does not duplicate those rules.'
assert_file_contains "$MOCK_LOG" 'lando|drush|config:export|-y'

# Export uses a stricter Config Ignore preflight than readiness: unknown module
# state blocks mutation rather than guessing.
UNKNOWN_IGNORE="$TMP_ROOT/unknown-ignore"
create_repo "$UNKNOWN_IGNORE" lando 'Unknown Ignore Export' full-export config/export
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/export'
export MOCK_CONFIG_STATUS='system.site'
export MOCK_PM_FAIL=true
export MOCK_EXPORT_PATH="$UNKNOWN_IGNORE/config/export"
unknown_ignore_output=$(capture_failure "$UNKNOWN_IGNORE" --yes)
assert_contains "$unknown_ignore_output" 'Config Ignore:         unavailable'
assert_contains "$unknown_ignore_output" 'Config Ignore module-state inspection failed'
assert_file_not_contains "$MOCK_LOG" 'config:export'

# A failed readiness preflight prevents export.
READINESS_FAIL="$TMP_ROOT/readiness-fail"
create_repo "$READINESS_FAIL" lando 'Readiness Failure Export' full-export config/expected
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/other'
export MOCK_EXPORT_PATH="$READINESS_FAIL/config/expected"
readiness_fail_output=$(capture_failure "$READINESS_FAIL" --yes)
assert_contains "$readiness_fail_output" 'does not match Drupal runtime config-sync path'
assert_contains "$readiness_fail_output" 'full-export readiness preflight failed'
assert_file_not_contains "$MOCK_LOG" 'config:export'

# Provider export failure can leave partial local changes. PLT reports them,
# leaves them in place, and fails without committing or pretending rollback.
PARTIAL="$TMP_ROOT/partial-failure"
create_repo "$PARTIAL" lando 'Partial Export Failure' full-export config/export
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/export'
export MOCK_CONFIG_STATUS='system.site'
export MOCK_EXPORT_PATH="$PARTIAL/config/export"
export MOCK_EXPORT_MODE=fail-partial
partial_output=$(capture_failure "$PARTIAL" --yes)
assert_contains "$partial_output" 'Export change summary for config/export:'
assert_contains "$partial_output" 'changed: 1'
assert_contains "$partial_output" 'provider-owned drush config:export failed'
grep -F 'partial: true' "$PARTIAL/config/export/system.site.yml" >/dev/null 2>&1 || fail 'partial export fixture change was unexpectedly rolled back'
git -C "$PARTIAL" diff --cached --quiet || fail 'failed export staged files unexpectedly'

# Explicit DDEV selection follows the same mutation contract.
DDEV="$TMP_ROOT/ddev-export"
create_repo "$DDEV" ddev 'DDEV Full Export' full-export config/export
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/var/www/html/config/export'
export MOCK_EXPORT_PATH="$DDEV/config/export"
export MOCK_EXPORT_MODE=nochange
ddev_output=$(cd "$DDEV" && bash "$CLI" config export --provider ddev --yes)
assert_contains "$ddev_output" 'Provider:              ddev'
assert_contains "$ddev_output" 'created: 0'
assert_contains "$ddev_output" 'changed: 0'
assert_contains "$ddev_output" 'deleted: 0'
assert_file_contains "$MOCK_LOG" 'ddev|drush|config:export|-y'

printf 'config export tests passed\n'
