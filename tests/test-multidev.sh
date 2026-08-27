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
SOURCE_LANDO="$TMP_ROOT/source-lando"
SOURCE_DDEV="$TMP_ROOT/source-ddev"
mkdir -p "$HOME" "$MOCK_BIN"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }
assert_file_contains() { grep -F "$2" "$1" >/dev/null 2>&1 || fail "expected $1 to contain [$2]"; }
assert_file_not_contains() { if grep -F "$2" "$1" >/dev/null 2>&1; then fail "expected $1 not to contain [$2]"; fi; }

cat > "$MOCK_BIN/terminus" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  auth:whoami)
    printf '%s\n' 'developer@example.com'
    ;;
  site:info)
    case "${3:-}" in
      --field=organization) printf '%s\n' "${MOCK_ORG:-Example Org}" ;;
      --field=framework) printf '%s\n' "${MOCK_FRAMEWORK:-drupal8}" ;;
      *) printf 'unexpected site:info arguments\n' >&2; exit 2 ;;
    esac
    ;;
  tag:list)
    printf '%s\n' "${MOCK_TAGS:-Example Group}"
    ;;
  connection:info)
    [ "${3:-}" = '--field=git_url' ] || { printf 'unexpected connection:info arguments\n' >&2; exit 2; }
    printf '%s\n' "${MOCK_GIT_URL:?MOCK_GIT_URL is required}"
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
    printf '%s\n' "$PWD" >> "${MOCK_START_LOG:?MOCK_START_LOG is required}"
    ;;
  info)
    printf '%s\n' "$PWD" >> "${MOCK_INFO_LOG:?MOCK_INFO_LOG is required}"
    [ "${MOCK_LANDO_INFO_FAIL:-false}" != true ] || exit 9
    printf '%s\n' "${MOCK_LANDO_URLS:-[\"http://localhost:49152\",\"http://example-runtime.test/\",\"https://example-runtime.test/\"]}"
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
    printf '%s\n' "$PWD" >> "${MOCK_START_LOG:?MOCK_START_LOG is required}"
    ;;
  describe)
    [ "${2:-}" = -j ] || exit 2
    printf '%s\n' "$PWD" >> "${MOCK_INFO_LOG:?MOCK_INFO_LOG is required}"
    [ "${MOCK_DDEV_INFO_FAIL:-false}" != true ] || exit 9
    printf '%s\n' "${MOCK_DDEV_JSON:-{\"raw\":{\"primary_url\":\"https://example-ddev.test\"}}}"
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$MOCK_BIN/ddev"

export PATH="$MOCK_BIN:$PATH"
export MOCK_START_LOG="$TMP_ROOT/start.log"
export MOCK_INFO_LOG="$TMP_ROOT/info.log"

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
    - pma.example-project.test
tooling:
  custom-check:
    service: appserver
    cmd: php -v
  drush:
    env:
      DRUSH_OPTIONS_URI: "https://provider-owned.example-project.test"
YAML
      ;;
    ddev)
      mkdir -p "$path/.ddev"
      cat > "$path/.ddev/config.yaml" <<'YAML'
name: example-ddev
type: drupal11
additional_hostnames:
  - alternate-example
YAML
      cat > "$path/.ddev/docker-compose.adminer.yaml" <<'YAML'
services:
  adminer:
    image: adminer:latest
YAML
      ;;
    *) fail "unknown fixture provider: $provider" ;;
  esac
  git -C "$path" add .
  git -C "$path" commit -qm 'Create provider fixture'
  git -C "$path" branch feature1
  git -C "$path" branch feature2
  git -C "$path" branch feature3
}

create_repo "$SOURCE_LANDO" lando
create_repo "$SOURCE_DDEV" ddev

export MOCK_GIT_URL="$SOURCE_LANDO"
export MOCK_TAGS='Example Group'
export MOCK_ORG='Example Org'
export MOCK_FRAMEWORK='drupal8'

bash "$CLI" config set root "$LOCAL_ROOT"
bash "$CLI" config set provider lando
bash "$CLI" config tag set 'Example Group' clients

# Dry-run resolves Pantheon metadata and routing but does not query or guess a provider URL.
dry_output=$(bash "$CLI" multidev example-site.feature1 --group migration --dry-run)
assert_contains "$dry_output" 'Pantheon multidev dry-run'
assert_contains "$dry_output" 'Tag:         Example Group'
assert_contains "$dry_output" 'Provider:    lando'
assert_contains "$dry_output" 'Local URL:   (provider runtime; available after checkout)'
assert_contains "$dry_output" "$LOCAL_ROOT/clients/multidev/migration/example-site-feature1"
[ ! -e "$LOCAL_ROOT/clients/multidev/migration/example-site-feature1" ] || fail 'dry-run created a checkout'
[ ! -s "$MOCK_INFO_LOG" ] || fail 'dry-run queried a local provider runtime'

# A real Lando checkout is cloned transactionally and receives only the local name override.
bash "$CLI" multidev example-site.feature1 --group migration >/dev/null
LANDO_DEST="$LOCAL_ROOT/clients/multidev/migration/example-site-feature1"
[ -d "$LANDO_DEST/.git" ] || fail 'Lando checkout was not cloned'
assert_eq "$(git -C "$LANDO_DEST" rev-parse --abbrev-ref HEAD)" 'feature1'
assert_file_contains "$LANDO_DEST/.lando.local.yml" 'name: example-site-feature1'
assert_file_not_contains "$LANDO_DEST/.lando.local.yml" 'DRUSH_OPTIONS_URI'
assert_file_contains "$LANDO_DEST/.git/info/exclude" '.lando.local.yml'
assert_file_contains "$LANDO_DEST/.lando.yml" 'type: phpmyadmin'
assert_file_contains "$LANDO_DEST/.lando.yml" 'type: redis'
assert_file_contains "$LANDO_DEST/.lando.yml" 'custom-check:'
assert_file_contains "$LANDO_DEST/.lando.yml" 'DRUSH_OPTIONS_URI: "https://provider-owned.example-project.test"'
assert_eq "$(git -C "$LANDO_DEST" status --porcelain)" ''
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get pantheon.site)" 'example-site'
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get pantheon.environment)" 'feature1'
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get pantheon.tag)" 'Example Group'
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get local.provider)" 'lando'
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get local.url)" 'https://example-runtime.test'

if bash "$CLI" multidev example-site.feature1 --group migration >/dev/null 2>&1; then
  fail 'existing destination was overwritten or reused'
fi

# Configured Tag routing must resolve to exactly one Pantheon Tag.
bash "$CLI" config tag set 'Another Group' another
MOCK_TAGS=$(printf 'Example Group\nAnother Group')
export MOCK_TAGS
if bash "$CLI" multidev example-site.feature2 --dry-run >/dev/null 2>&1; then
  fail 'ambiguous Pantheon Tag routing was accepted'
fi
export MOCK_TAGS='Unmapped Group'
if bash "$CLI" multidev example-site.feature2 --dry-run >/dev/null 2>&1; then
  fail 'unmatched Pantheon Tag routing was accepted'
fi

# With no Tag mappings, checkouts route directly under <root>/multidev.
bash "$CLI" config tag unset 'Example Group'
bash "$CLI" config tag unset 'Another Group'
export MOCK_TAGS='Anything'
no_tag_output=$(bash "$CLI" multidev example-site.feature2 --dry-run)
assert_contains "$no_tag_output" 'Tag:         (no configured Tag routing)'
assert_contains "$no_tag_output" "$LOCAL_ROOT/multidev/example-site-feature2"

# auto detects an unambiguous provider. URL discovery is best effort and never blocks checkout creation.
bash "$CLI" config set provider auto
export MOCK_LANDO_INFO_FAIL=true
bash "$CLI" multidev example-site.feature2 >/dev/null
unset MOCK_LANDO_INFO_FAIL
AUTO_DEST="$LOCAL_ROOT/multidev/example-site-feature2"
assert_file_contains "$AUTO_DEST/.lando.local.yml" 'name: example-site-feature2'
assert_file_not_contains "$AUTO_DEST/.lando.local.yml" 'DRUSH_OPTIONS_URI'
assert_eq "$(git config --file "$AUTO_DEST/.git/pantheon-local-tools/state" --get local.provider)" 'lando'
if git config --file "$AUTO_DEST/.git/pantheon-local-tools/state" --get local.url >/dev/null 2>&1; then
  fail 'failed provider URL discovery still recorded a URL'
fi

# DDEV is first-class, preserves extra configuration, and records provider-reported URL metadata.
export MOCK_GIT_URL="$SOURCE_DDEV"
bash "$CLI" config set provider ddev
bash "$CLI" multidev example-ddev.feature1 >/dev/null
DDEV_DEST="$LOCAL_ROOT/multidev/example-ddev-feature1"
[ -f "$DDEV_DEST/.ddev/config.yaml" ] || fail 'DDEV base configuration is missing after clone'
assert_file_contains "$DDEV_DEST/.ddev/config.local.yaml" 'name: example-ddev-feature1'
assert_file_contains "$DDEV_DEST/.git/info/exclude" '.ddev/config.local.yaml'
assert_file_contains "$DDEV_DEST/.ddev/config.yaml" 'alternate-example'
assert_file_contains "$DDEV_DEST/.ddev/docker-compose.adminer.yaml" 'image: adminer:latest'
assert_eq "$(git -C "$DDEV_DEST" status --porcelain)" ''
assert_eq "$(git config --file "$DDEV_DEST/.git/pantheon-local-tools/state" --get local.provider)" 'ddev'
assert_eq "$(git config --file "$DDEV_DEST/.git/pantheon-local-tools/state" --get local.url)" 'https://example-ddev.test'

# Runtime start is opt-in, happens only after finalization, and refreshes provider URL metadata.
export MOCK_GIT_URL="$SOURCE_LANDO"
bash "$CLI" config set provider lando
start_output=$(bash "$CLI" multidev example-site.feature3 --start)
START_DEST="$LOCAL_ROOT/multidev/example-site-feature3"
assert_file_contains "$MOCK_START_LOG" "$START_DEST"
assert_contains "$start_output" 'Runtime URL:  https://example-runtime.test'
assert_eq "$(git config --file "$START_DEST/.git/pantheon-local-tools/state" --get local.url)" 'https://example-runtime.test'

# Failed clones must not leave the final checkout path behind.
export MOCK_GIT_URL="$TMP_ROOT/does-not-exist"
if bash "$CLI" multidev failed-site.feature1 >/dev/null 2>&1; then
  fail 'failed Git clone unexpectedly succeeded'
fi
[ ! -e "$LOCAL_ROOT/multidev/failed-site-feature1" ] || fail 'failed clone left a final destination behind'

printf 'multidev tests passed\n'
