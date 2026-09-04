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
assert_file_contains() { grep -F "$2" "$1" >/dev/null 2>&1 || fail "expected $1 to contain [$2]"; }
assert_file_not_contains() { if [ -f "$1" ] && grep -F "$2" "$1" >/dev/null 2>&1; then fail "expected $1 not to contain [$2]"; fi; }
assert_line() {
  local file=$1 number=$2 expected=$3 actual
  actual=$(sed -n "${number}p" "$file")
  [ "$actual" = "$expected" ] || fail "expected line $number [$expected], got [$actual]"
}

cat > "$MOCK_BIN/lando" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
line='lando'
for arg in "$@"; do line="$line|$arg"; done
printf '%s\n' "$line" >> "${MOCK_LOG:?}"
if [ -n "${MOCK_FAIL_MATCH:-}" ]; then
  case "$line" in *"$MOCK_FAIL_MATCH"*) exit 9 ;; esac
fi
case "$line" in
  'lando|drush|core:status|--field=config-sync')
    printf '%s\n' "${MOCK_RUNTIME_CONFIG_PATH:-/app/config/custom-export}"
    ;;
  'lando|drush|config:status|--format=list')
    [ "${MOCK_MUTATE_GIT:-false}" != true ] || printf 'inspection mutation\n' >> README.md
    [ -z "${MOCK_CONFIG_STATUS:-}" ] || printf '%s\n' "$MOCK_CONFIG_STATUS"
    ;;
  'lando|drush|pm:list|--type=module|--status=enabled|--field=name')
    [ "${MOCK_PM_FAIL:-false}" != true ] || exit 10
    printf '%s\n' "${MOCK_MODULES:-node}"
    ;;
esac
MOCK
chmod +x "$MOCK_BIN/lando"

cat > "$MOCK_BIN/ddev" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
line='ddev'
for arg in "$@"; do line="$line|$arg"; done
printf '%s\n' "$line" >> "${MOCK_LOG:?}"
if [ -n "${MOCK_FAIL_MATCH:-}" ]; then
  case "$line" in *"$MOCK_FAIL_MATCH"*) exit 9 ;; esac
fi
case "$line" in
  'ddev|drush|core:status|--field=config-sync')
    printf '%s\n' "${MOCK_RUNTIME_CONFIG_PATH:-/var/www/html/config/custom-export}"
    ;;
  'ddev|drush|config:status|--format=list')
    [ "${MOCK_MUTATE_GIT:-false}" != true ] || printf 'inspection mutation\n' >> README.md
    [ -z "${MOCK_CONFIG_STATUS:-}" ] || printf '%s\n' "$MOCK_CONFIG_STATUS"
    ;;
  'ddev|drush|pm:list|--type=module|--status=enabled|--field=name')
    [ "${MOCK_PM_FAIL:-false}" != true ] || exit 10
    printf '%s\n' "${MOCK_MODULES:-node}"
    ;;
esac
MOCK
chmod +x "$MOCK_BIN/ddev"

export PATH="$MOCK_BIN:$PATH"
export MOCK_LOG
export PANTHEON_LOCAL_CONFIG="$TMP_ROOT/plt-config"

reset_mocks() {
  : > "$MOCK_LOG"
  unset MOCK_FAIL_MATCH MOCK_CONFIG_STATUS MOCK_MODULES MOCK_PM_FAIL MOCK_RUNTIME_CONFIG_PATH MOCK_MUTATE_GIT || true
}

create_repo() {
  local path=$1 provider=$2 tag=$3 strategy=$4 config_path=$5 directory
  mkdir -p "$path/$config_path"
  git -C "$path" init -q
  git -C "$path" config user.name 'Test User'
  git -C "$path" config user.email 'test@example.com'
  printf 'fixture\n' > "$path/README.md"
  printf 'uuid: fixture\n' > "$path/$config_path/system.site.yml"

  case "$provider" in
    lando) printf 'name: example-site\nrecipe: pantheon\n' > "$path/.lando.yml" ;;
    ddev)
      mkdir -p "$path/.ddev"
      printf 'name: example-site\ntype: drupal11\n' > "$path/.ddev/config.yaml"
      ;;
    *) fail "unknown provider fixture: $provider" ;;
  esac

  git -C "$path" add .
  git -C "$path" commit -qm 'Create readiness fixture'
  mkdir -p "$path/.git/pantheon-local-tools"
  git config --file "$path/.git/pantheon-local-tools/state" pantheon.tag "$tag"
  git config --file "$path/.git/pantheon-local-tools/state" local.provider "$provider"

  directory=$(basename "$path")
  bash "$CLI" config tag set "$tag" "$directory"
  bash "$CLI" config tag profile set "$tag" config-strategy "$strategy"
  bash "$CLI" config tag profile set "$tag" config-path "$config_path"
}

assert_contains "$(bash "$CLI" --help)" 'pantheon-local readiness [--provider ddev|lando]'
readiness_help=$(bash "$CLI" readiness --help)
assert_contains "$readiness_help" 'full-export'
assert_contains "$readiness_help" 'overlay-delta'
assert_contains "$readiness_help" 'No drush config:export / cex is run.'
assert_contains "$readiness_help" 'still exit 0 when inspection succeeds'
assert_contains "$readiness_help" 'Config Ignore detection is advisory.'

# Synchronized full-export config with a nonstandard configured path is ready.
SYNCED="$TMP_ROOT/synced"
create_repo "$SYNCED" lando 'Full Export Synced' full-export config/custom-export
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/custom-export'
synced_output=$(cd "$SYNCED" && bash "$CLI" readiness)
assert_contains "$synced_output" 'Pantheon Tag:          Full Export Synced'
assert_contains "$synced_output" 'Config strategy:       full-export'
assert_contains "$synced_output" 'Configured config path: config/custom-export'
assert_contains "$synced_output" 'Drupal configuration:  synchronized'
assert_contains "$synced_output" 'Config Ignore:         disabled'
assert_contains "$synced_output" 'Config export:         not performed'
assert_contains "$synced_output" 'Git working tree:      clean'
assert_contains "$synced_output" 'Readiness:             ready'
assert_line "$MOCK_LOG" 1 'lando|drush|core:status|--field=config-sync'
assert_line "$MOCK_LOG" 2 'lando|drush|config:status|--format=list'
assert_line "$MOCK_LOG" 3 'lando|drush|pm:list|--type=module|--status=enabled|--field=name'
assert_file_not_contains "$MOCK_LOG" 'config:export'
assert_file_not_contains "$MOCK_LOG" 'cex'

# Differences are a successful inspection result, including when Config Ignore is enabled.
DRIFT="$TMP_ROOT/drift"
create_repo "$DRIFT" lando 'Full Export Drift' full-export config/site-export
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/site-export'
export MOCK_CONFIG_STATUS=$'system.site\nviews.view.example'
export MOCK_MODULES=$'node\nconfig_ignore'
drift_output=$(cd "$DRIFT" && bash "$CLI" readiness)
assert_contains "$drift_output" 'Drupal configuration:  differences detected'
assert_contains "$drift_output" 'Config Ignore:         enabled'
assert_contains "$drift_output" 'Readiness:             review configuration differences'
assert_contains "$drift_output" 'Review them before choosing any export action.'
assert_contains "$drift_output" 'PLT does not reinterpret its matching rules'
assert_file_not_contains "$MOCK_LOG" 'config:export'
assert_file_not_contains "$MOCK_LOG" 'cex'

# Config Ignore detection failure is advisory and reported without guessing.
UNKNOWN_IGNORE="$TMP_ROOT/unknown-ignore"
create_repo "$UNKNOWN_IGNORE" lando 'Full Export Unknown Ignore' full-export config/exported
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/exported'
export MOCK_CONFIG_STATUS='system.site'
export MOCK_PM_FAIL=true
unknown_output=$(cd "$UNKNOWN_IGNORE" && bash "$CLI" readiness)
assert_contains "$unknown_output" 'Config Ignore:         unavailable'
assert_contains "$unknown_output" 'Readiness:             review configuration differences'
assert_contains "$unknown_output" 'Config Ignore state was unavailable'

# A pre-existing dirty tree is reported as review state and preserved.
DIRTY="$TMP_ROOT/dirty"
create_repo "$DIRTY" lando 'Full Export Dirty' full-export config/exported-dirty
printf 'local notes\n' > "$DIRTY/notes.txt"
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/exported-dirty'
dirty_output=$(cd "$DIRTY" && bash "$CLI" readiness)
assert_contains "$dirty_output" 'Drupal configuration:  synchronized'
assert_contains "$dirty_output" 'Git working tree:      modified'
assert_contains "$dirty_output" 'Readiness:             review working tree'
[ -f "$DIRTY/notes.txt" ] || fail 'readiness removed an existing untracked file'

# DDEV follows the same provider-owned Drush inspection contract.
DDEV="$TMP_ROOT/ddev"
create_repo "$DDEV" ddev 'Full Export DDEV' full-export config/ddev-export
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/var/www/html/config/ddev-export'
ddev_output=$(cd "$DDEV" && bash "$CLI" readiness)
assert_contains "$ddev_output" 'Provider:              ddev'
assert_contains "$ddev_output" 'Readiness:             ready'
assert_line "$MOCK_LOG" 1 'ddev|drush|core:status|--field=config-sync'
assert_line "$MOCK_LOG" 2 'ddev|drush|config:status|--format=list'
assert_line "$MOCK_LOG" 3 'ddev|drush|pm:list|--type=module|--status=enabled|--field=name'

# Overlay profiles fail closed before invoking provider commands.
OVERLAY="$TMP_ROOT/overlay"
create_repo "$OVERLAY" lando 'Overlay Example' overlay-delta config/overrides
reset_mocks
if (cd "$OVERLAY" && bash "$CLI" readiness >/dev/null 2>&1); then
  fail 'readiness applied full-export behavior to overlay-delta'
fi
[ ! -s "$MOCK_LOG" ] || fail 'overlay-delta refusal invoked provider commands'

# Missing configured directory fails before provider-owned Drush.
MISSING_DIR="$TMP_ROOT/missing-dir"
create_repo "$MISSING_DIR" lando 'Missing Directory' full-export config/will-disappear
rm -rf "$MISSING_DIR/config/will-disappear"
reset_mocks
if (cd "$MISSING_DIR" && bash "$CLI" readiness >/dev/null 2>&1); then
  fail 'readiness accepted a missing configured config-path directory'
fi
[ ! -s "$MOCK_LOG" ] || fail 'missing config path invoked provider commands'

# Runtime Drupal sync path must agree with the configured profile path.
MISMATCH="$TMP_ROOT/mismatch"
create_repo "$MISMATCH" lando 'Path Mismatch' full-export config/expected
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/other'
if (cd "$MISMATCH" && bash "$CLI" readiness >/dev/null 2>&1); then
  fail 'readiness accepted a runtime config-sync path mismatch'
fi
assert_line "$MOCK_LOG" 1 'lando|drush|core:status|--field=config-sync'
assert_file_not_contains "$MOCK_LOG" 'config:status'

# Provider-owned config:status failure is fatal and does not continue to module inspection.
DRUSH_FAIL="$TMP_ROOT/drush-fail"
create_repo "$DRUSH_FAIL" lando 'Drush Failure' full-export config/failure
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/failure'
export MOCK_FAIL_MATCH='lando|drush|config:status|--format=list'
if (cd "$DRUSH_FAIL" && bash "$CLI" readiness >/dev/null 2>&1); then
  fail 'readiness succeeded after config:status failure'
fi
assert_file_contains "$MOCK_LOG" 'lando|drush|config:status|--format=list'
assert_file_not_contains "$MOCK_LOG" 'pm:list'

# Inspection must fail if a delegated Drush command changes Git-visible source state.
MUTATED="$TMP_ROOT/mutated"
create_repo "$MUTATED" lando 'Inspection Mutation' full-export config/mutation
reset_mocks
export MOCK_RUNTIME_CONFIG_PATH='/app/config/mutation'
export MOCK_MUTATE_GIT=true
if (cd "$MUTATED" && bash "$CLI" readiness >/dev/null 2>&1); then
  fail 'readiness reported success after inspection mutated the working tree'
fi
grep -F 'inspection mutation' "$MUTATED/README.md" >/dev/null 2>&1 || fail 'mutation fixture did not mutate tracked source'

printf 'readiness tests passed\n'
