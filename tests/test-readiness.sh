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

capture_readiness_failure() {
  local repo=$1
  shift
  local output status
  set +e
  output=$(cd "$repo" && bash "$CLI" readiness "$@" 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "expected readiness to fail for $repo"
  printf '%s\n' "$output"
}

assert_contains "$(bash "$CLI" --help)" 'pantheon-local readiness [--provider ddev|lando]'
readiness_help=$(bash "$CLI" readiness --help)
assert_contains "$readiness_help" 'full-export'
assert_contains "$readiness_help" 'overlay-delta'
assert_contains "$readiness_help" 'protected partial override set'
assert_contains "$readiness_help" 'No provider-owned Drush command is invoked'
assert_contains "$readiness_help" 'No drush config:export / cex is run.'
assert_contains "$readiness_help" 'still exit 0 when inspection succeeds'
assert_contains "$readiness_help" 'Owning validation remains fail-closed'
assert_contains "$readiness_help" 'Config Ignore detection is advisory for full-export.'

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

# Overlay profiles report the protected boundary but fail closed without provider/Drush calls.
OVERLAY="$TMP_ROOT/overlay"
create_repo "$OVERLAY" lando 'Shared Platform Example' overlay-delta config/site-overrides
reset_mocks
overlay_output=$(capture_readiness_failure "$OVERLAY")
assert_contains "$overlay_output" 'Pantheon Tag:          Shared Platform Example'
assert_contains "$overlay_output" 'Config strategy:       overlay-delta'
assert_contains "$overlay_output" 'Configured config path: config/site-overrides'
assert_contains "$overlay_output" 'Provider:              not invoked'
assert_contains "$overlay_output" 'Delta interpretation:  protected partial override set'
assert_contains "$overlay_output" 'Drupal configuration:  not interpreted as full export'
assert_contains "$overlay_output" 'Owning validation:     unavailable'
assert_contains "$overlay_output" 'Config Ignore:         not inspected'
assert_contains "$overlay_output" 'Config export:         not performed'
assert_contains "$overlay_output" 'Git working tree:      clean'
assert_contains "$overlay_output" 'Readiness:             unavailable'
assert_contains "$overlay_output" 'Missing YAML, directory size, and file count are not interpreted as overlay drift.'
assert_contains "$overlay_output" 'No provider or Drush command was invoked.'
assert_not_contains "$overlay_output" 'differences detected'
assert_not_contains "$overlay_output" 'synchronized'
[ ! -s "$MOCK_LOG" ] || fail 'overlay-delta inspection invoked provider commands'

# A valid explicit provider flag is syntax only while overlay validation is unavailable.
reset_mocks
overlay_provider_output=$(capture_readiness_failure "$OVERLAY" --provider ddev)
assert_contains "$overlay_provider_output" 'Provider:              not invoked'
[ ! -s "$MOCK_LOG" ] || fail 'overlay-delta --provider invoked provider commands'

# Invalid provider values still fail at the public CLI boundary.
reset_mocks
invalid_provider_output=$(capture_readiness_failure "$OVERLAY" --provider other)
assert_contains "$invalid_provider_output" '--provider must be ddev or lando'
[ ! -s "$MOCK_LOG" ] || fail 'invalid provider value invoked provider commands'

# Empty overlay directories do not become missing-drift findings.
OVERLAY_EMPTY="$TMP_ROOT/overlay-empty"
create_repo "$OVERLAY_EMPTY" lando 'Empty Overlay Example' overlay-delta config/empty-overrides
git -C "$OVERLAY_EMPTY" rm -q config/empty-overrides/system.site.yml
git -C "$OVERLAY_EMPTY" commit -qm 'Make overlay directory empty'
mkdir -p "$OVERLAY_EMPTY/config/empty-overrides"
reset_mocks
empty_output=$(capture_readiness_failure "$OVERLAY_EMPTY")
assert_contains "$empty_output" 'Delta interpretation:  protected partial override set'
assert_contains "$empty_output" 'Owning validation:     unavailable'
assert_not_contains "$empty_output" 'differences detected'
[ ! -s "$MOCK_LOG" ] || fail 'empty overlay inspection invoked provider commands'

# Large overlay directories have no special readiness meaning either.
OVERLAY_LARGE="$TMP_ROOT/overlay-large"
create_repo "$OVERLAY_LARGE" lando 'Large Overlay Example' overlay-delta config/many-overrides
index=1
while [ "$index" -le 40 ]; do
  printf 'id: %s\n' "$index" > "$OVERLAY_LARGE/config/many-overrides/example.$index.yml"
  index=$((index + 1))
done
git -C "$OVERLAY_LARGE" add config/many-overrides
git -C "$OVERLAY_LARGE" commit -qm 'Add many overlay fixtures'
reset_mocks
large_output=$(capture_readiness_failure "$OVERLAY_LARGE")
assert_contains "$large_output" 'Owning validation:     unavailable'
assert_contains "$large_output" 'Missing YAML, directory size, and file count are not interpreted as overlay drift.'
assert_not_contains "$large_output" 'differences detected'
[ ! -s "$MOCK_LOG" ] || fail 'large overlay inspection invoked provider commands'

# A pre-existing dirty overlay tree is reported and preserved.
OVERLAY_DIRTY="$TMP_ROOT/overlay-dirty"
create_repo "$OVERLAY_DIRTY" lando 'Dirty Overlay Example' overlay-delta config/dirty-overrides
printf 'local overlay notes\n' > "$OVERLAY_DIRTY/local-notes.txt"
reset_mocks
overlay_dirty_output=$(capture_readiness_failure "$OVERLAY_DIRTY")
assert_contains "$overlay_dirty_output" 'Git working tree:      modified'
assert_contains "$overlay_dirty_output" 'Readiness:             unavailable'
[ -f "$OVERLAY_DIRTY/local-notes.txt" ] || fail 'overlay readiness removed an existing untracked file'
[ ! -s "$MOCK_LOG" ] || fail 'dirty overlay inspection invoked provider commands'

# Missing overlay directory fails before provider commands.
OVERLAY_MISSING="$TMP_ROOT/overlay-missing"
create_repo "$OVERLAY_MISSING" lando 'Missing Overlay Example' overlay-delta config/missing-overrides
rm -rf "$OVERLAY_MISSING/config/missing-overrides"
reset_mocks
overlay_missing_output=$(capture_readiness_failure "$OVERLAY_MISSING")
assert_contains "$overlay_missing_output" 'configured overlay-delta config-path does not exist as a directory: config/missing-overrides'
[ ! -s "$MOCK_LOG" ] || fail 'missing overlay path invoked provider commands'

# A lexically safe path that escapes through a symlink is rejected.
OVERLAY_SYMLINK="$TMP_ROOT/overlay-symlink"
create_repo "$OVERLAY_SYMLINK" lando 'Symlink Overlay Example' overlay-delta config/external-overrides
rm -rf "$OVERLAY_SYMLINK/config/external-overrides"
mkdir -p "$TMP_ROOT/external-overrides"
ln -s "$TMP_ROOT/external-overrides" "$OVERLAY_SYMLINK/config/external-overrides"
reset_mocks
symlink_output=$(capture_readiness_failure "$OVERLAY_SYMLINK")
assert_contains "$symlink_output" 'config-path escapes the project root through filesystem links'
[ ! -s "$MOCK_LOG" ] || fail 'escaping overlay path invoked provider commands'

# Missing configured full-export directory fails before provider-owned Drush.
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
