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
[ "${1:-}" = start ] || exit 2
printf '%s\n' "$PWD" >> "${MOCK_START_LOG:?MOCK_START_LOG is required}"
MOCK
chmod +x "$MOCK_BIN/lando"

cat > "$MOCK_BIN/ddev" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = start ] || exit 2
printf '%s\n' "$PWD" >> "${MOCK_START_LOG:?MOCK_START_LOG is required}"
MOCK
chmod +x "$MOCK_BIN/ddev"

export PATH="$MOCK_BIN:$PATH"
export MOCK_START_LOG="$TMP_ROOT/start.log"

create_repo() {
  local path=$1 provider=$2
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name 'Test User'
  git -C "$path" config user.email 'test@example.com'
  case "$provider" in
    lando)
      printf 'name: example-site\nrecipe: pantheon\n' > "$path/.lando.yml"
      ;;
    ddev)
      mkdir -p "$path/.ddev"
      printf 'name: example-ddev\ntype: drupal11\n' > "$path/.ddev/config.yaml"
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

# Dry-run resolves Pantheon metadata and routing but makes no checkout directories.
dry_output=$(bash "$CLI" multidev example-site.feature1 --group migration --dry-run)
assert_contains "$dry_output" 'Pantheon multidev dry-run'
assert_contains "$dry_output" 'Tag:         Example Group'
assert_contains "$dry_output" 'Provider:    lando'
assert_contains "$dry_output" "$LOCAL_ROOT/clients/multidev/migration/example-site-feature1"
[ ! -e "$LOCAL_ROOT/clients/multidev/migration/example-site-feature1" ] || fail 'dry-run created a checkout'

# A real Lando checkout is cloned transactionally and receives only local overrides.
bash "$CLI" multidev example-site.feature1 --group migration >/dev/null
LANDO_DEST="$LOCAL_ROOT/clients/multidev/migration/example-site-feature1"
[ -d "$LANDO_DEST/.git" ] || fail 'Lando checkout was not cloned'
assert_eq "$(git -C "$LANDO_DEST" rev-parse --abbrev-ref HEAD)" 'feature1'
assert_file_contains "$LANDO_DEST/.lando.local.yml" 'name: example-site-feature1'
assert_file_contains "$LANDO_DEST/.lando.local.yml" 'DRUSH_OPTIONS_URI: "http://example-site-feature1.lndo.site"'
assert_file_contains "$LANDO_DEST/.git/info/exclude" '.lando.local.yml'
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get pantheon.site)" 'example-site'
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get pantheon.environment)" 'feature1'
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get pantheon.tag)" 'Example Group'
assert_eq "$(git config --file "$LANDO_DEST/.git/pantheon-local-tools/state" --get local.provider)" 'lando'

if bash "$CLI" multidev example-site.feature1 --group migration >/dev/null 2>&1; then
  fail 'existing destination was overwritten or reused'
fi

# Configured Tag routing must resolve to exactly one Pantheon Tag.
bash "$CLI" config tag set 'Another Group' another
export MOCK_TAGS=$(printf 'Example Group\nAnother Group')
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

# auto detects an unambiguous provider from the cloned project.
bash "$CLI" config set provider auto
bash "$CLI" multidev example-site.feature2 >/dev/null
AUTO_DEST="$LOCAL_ROOT/multidev/example-site-feature2"
assert_file_contains "$AUTO_DEST/.lando.local.yml" 'name: example-site-feature2'
assert_eq "$(git config --file "$AUTO_DEST/.git/pantheon-local-tools/state" --get local.provider)" 'lando'

# DDEV is a first-class provider and writes its local override without touching shared config.
export MOCK_GIT_URL="$SOURCE_DDEV"
bash "$CLI" config set provider ddev
bash "$CLI" multidev example-ddev.feature1 >/dev/null
DDEV_DEST="$LOCAL_ROOT/multidev/example-ddev-feature1"
[ -f "$DDEV_DEST/.ddev/config.yaml" ] || fail 'DDEV base configuration is missing after clone'
assert_file_contains "$DDEV_DEST/.ddev/config.local.yaml" 'name: example-ddev-feature1'
assert_file_contains "$DDEV_DEST/.git/info/exclude" '.ddev/config.local.yaml'
assert_eq "$(git config --file "$DDEV_DEST/.git/pantheon-local-tools/state" --get local.provider)" 'ddev'
assert_eq "$(git config --file "$DDEV_DEST/.git/pantheon-local-tools/state" --get local.url)" 'https://example-ddev-feature1.ddev.site'

# Runtime start is opt-in and happens only after the completed checkout is in its final path.
export MOCK_GIT_URL="$SOURCE_LANDO"
bash "$CLI" config set provider lando
bash "$CLI" multidev example-site.feature3 --start >/dev/null
START_DEST="$LOCAL_ROOT/multidev/example-site-feature3"
assert_file_contains "$MOCK_START_LOG" "$START_DEST"

# Failed clones must not leave the final checkout path behind.
export MOCK_GIT_URL="$TMP_ROOT/does-not-exist"
if bash "$CLI" multidev failed-site.feature1 >/dev/null 2>&1; then
  fail 'failed Git clone unexpectedly succeeded'
fi
[ ! -e "$LOCAL_ROOT/multidev/failed-site-feature1" ] || fail 'failed clone left a final destination behind'

printf 'multidev tests passed\n'
