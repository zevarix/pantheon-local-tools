#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }

cat > "$MOCK_BIN/lando" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = info ] || exit 2
[ "${MOCK_LANDO_FAIL:-false}" != true ] || exit 9
printf '%s\n' "${MOCK_LANDO_URLS:-[\"http://localhost:49152\",\"http://example-runtime.test/\",\"https://example-runtime.test/\"]}"
MOCK
chmod +x "$MOCK_BIN/lando"

cat > "$MOCK_BIN/ddev" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = describe ] || exit 2
[ "${2:-}" = -j ] || exit 2
[ "${MOCK_DDEV_FAIL:-false}" != true ] || exit 9
printf '%s\n' "${MOCK_DDEV_JSON:-{\"raw\":{\"primary_url\":\"https://example-ddev.test\"}}}"
MOCK
chmod +x "$MOCK_BIN/ddev"

export PATH="$MOCK_BIN:$PATH"

create_repo() {
  local path=$1 provider=$2
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name 'Test User'
  git -C "$path" config user.email 'test@example.com'

  case "$provider" in
    lando)
      cat > "$path/.lando.yml" <<'YAML'
name: example-site
recipe: pantheon
services:
  pma:
    type: phpmyadmin
  cache:
    type: redis
proxy:
  pma:
    - pma.example-runtime.test
tooling:
  custom-check:
    service: appserver
    cmd: php -v
YAML
      ;;
    ddev)
      mkdir -p "$path/.ddev"
      printf 'name: example-site\ntype: drupal11\nadditional_hostnames:\n  - alternate-example\n' > "$path/.ddev/config.yaml"
      cat > "$path/.ddev/docker-compose.adminer.yaml" <<'YAML'
services:
  adminer:
    image: adminer:latest
YAML
      ;;
    *) fail "unknown provider fixture: $provider" ;;
  esac

  printf 'fixture\n' > "$path/README.md"
  git -C "$path" add .
  git -C "$path" commit -qm 'Create status fixture'
}

assert_contains "$(bash "$CLI" --help)" 'pantheon-local status'

MANAGED="$TMP_ROOT/managed"
create_repo "$MANAGED" lando
mkdir -p "$MANAGED/subdir" "$MANAGED/.git/pantheon-local-tools"
MANAGED_PHYSICAL=$(cd "$MANAGED" && pwd -P)
STATE="$MANAGED/.git/pantheon-local-tools/state"
git config --file "$STATE" pantheon.site example-site
git config --file "$STATE" pantheon.environment feature1
git config --file "$STATE" pantheon.tag 'Example Group'
git config --file "$STATE" local.provider lando
git config --file "$STATE" local.name example-site-feature1
git config --file "$STATE" local.url http://stale-recorded.example.test

LANDO_CONFIG_BEFORE=$(git -C "$MANAGED" hash-object .lando.yml)
managed_output=$(cd "$MANAGED/subdir" && bash "$CLI" status)
assert_contains "$managed_output" "Directory:       $MANAGED_PHYSICAL"
assert_contains "$managed_output" 'Managed:         yes'
assert_contains "$managed_output" 'Pantheon:        example-site.feature1'
assert_contains "$managed_output" 'Tag:             Example Group'
assert_contains "$managed_output" 'Provider:        lando'
assert_contains "$managed_output" 'Provider config: present'
assert_contains "$managed_output" 'Local name:      example-site-feature1'
assert_contains "$managed_output" 'Local URL:       https://example-runtime.test'
assert_contains "$managed_output" 'URL source:      provider runtime'
assert_contains "$managed_output" 'Git state:       clean'
assert_contains "$managed_output" 'Database source: (not recorded)'
assert_contains "$managed_output" 'Files source:    (not recorded)'
[ "$(git -C "$MANAGED" hash-object .lando.yml)" = "$LANDO_CONFIG_BEFORE" ] || fail 'status changed Lando project configuration'
assert_contains "$(cat "$MANAGED/.lando.yml")" 'type: phpmyadmin'
assert_contains "$(cat "$MANAGED/.lando.yml")" 'type: redis'
assert_contains "$(cat "$MANAGED/.lando.yml")" 'custom-check:'

# Runtime discovery failure falls back to recorded state without starting or mutating Lando.
export MOCK_LANDO_FAIL=true
fallback_output=$(cd "$MANAGED" && bash "$CLI" status)
unset MOCK_LANDO_FAIL
assert_contains "$fallback_output" 'Local URL:       http://stale-recorded.example.test'
assert_contains "$fallback_output" 'URL source:      recorded fallback'

# Component-specific provenance remains independent.
git config --file "$STATE" data.database-source test
git config --file "$STATE" data.files-source live
component_output=$(cd "$MANAGED" && bash "$CLI" status)
assert_contains "$component_output" 'Database source: test'
assert_contains "$component_output" 'Files source:    live'
git config --file "$STATE" --unset-all data.database-source
git config --file "$STATE" --unset-all data.files-source

# Legacy single-source state is interpreted as both components without mutating state.
git config --file "$STATE" data.source legacy-env
legacy_output=$(cd "$MANAGED" && bash "$CLI" status)
assert_contains "$legacy_output" 'Database source: legacy-env'
assert_contains "$legacy_output" 'Files source:    legacy-env'
[ "$(git config --file "$STATE" --get data.source)" = legacy-env ] || fail 'status mutated legacy provenance'
git config --file "$STATE" --unset-all data.source

printf 'dirty\n' >> "$MANAGED/README.md"
dirty_output=$(cd "$MANAGED" && bash "$CLI" status)
assert_contains "$dirty_output" 'Git state:       modified'
git -C "$MANAGED" checkout -q -- README.md

UNMANAGED="$TMP_ROOT/unmanaged"
create_repo "$UNMANAGED" ddev
DDEV_CONFIG_BEFORE=$(git -C "$UNMANAGED" hash-object .ddev/config.yaml)
DDEV_EXTRA_BEFORE=$(git -C "$UNMANAGED" hash-object .ddev/docker-compose.adminer.yaml)
unmanaged_output=$(cd "$UNMANAGED" && bash "$CLI" status)
assert_contains "$unmanaged_output" 'Managed:         no'
assert_contains "$unmanaged_output" 'Pantheon:        (not recorded)'
assert_contains "$unmanaged_output" 'Provider:        ddev (detected)'
assert_contains "$unmanaged_output" 'Provider config: present'
assert_contains "$unmanaged_output" 'Local name:      (not recorded)'
assert_contains "$unmanaged_output" 'Local URL:       https://example-ddev.test'
assert_contains "$unmanaged_output" 'URL source:      provider runtime'
assert_contains "$unmanaged_output" 'Database source: (not recorded)'
assert_contains "$unmanaged_output" 'Files source:    (not recorded)'
[ "$(git -C "$UNMANAGED" hash-object .ddev/config.yaml)" = "$DDEV_CONFIG_BEFORE" ] || fail 'status changed DDEV base configuration'
[ "$(git -C "$UNMANAGED" hash-object .ddev/docker-compose.adminer.yaml)" = "$DDEV_EXTRA_BEFORE" ] || fail 'status changed DDEV extra service configuration'

# The installed command is a symlink, so the router must resolve its real script directory.
mkdir -p "$TMP_ROOT/symlink-bin"
ln -s "$CLI" "$TMP_ROOT/symlink-bin/pantheon-local"
symlink_output=$(cd "$MANAGED" && "$TMP_ROOT/symlink-bin/pantheon-local" status)
assert_contains "$symlink_output" 'Pantheon:        example-site.feature1'

if (cd "$TMP_ROOT" && bash "$CLI" status >/dev/null 2>&1); then
  fail 'status unexpectedly succeeded outside a Git checkout'
fi

if (cd "$MANAGED" && bash "$CLI" status extra >/dev/null 2>&1); then
  fail 'status unexpectedly accepted an extra argument'
fi

printf 'status tests passed\n'
