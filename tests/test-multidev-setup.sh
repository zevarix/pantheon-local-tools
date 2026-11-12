#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-$REPO_ROOT/bin/pantheon-local}
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export HOME="$TMP/home" PANTHEON_LOCAL_CONFIG="$TMP/config"
export MOCK_LOG="$TMP/provider.log" MOCK_TERMINUS_LOG="$TMP/terminus.log"
export MOCK_GIT_URL="$TMP/source-lando" MOCK_FAIL_MATCH=''
MOCK_BIN="$TMP/bin"
ROOT="$TMP/sites"
mkdir -p "$MOCK_BIN" "$HOME"
: > "$MOCK_LOG"
: > "$MOCK_TERMINUS_LOG"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { case "$1" in *"$2"*) ;; *) fail "expected [$2] in [$1]" ;; esac; }
line_is() {
  local actual
  actual=$(sed -n "${2}p" "$1")
  [ "$actual" = "$3" ] || fail "line $2 expected [$3], got [$actual]"
}
config_is() {
  local actual
  actual=$(git config --file "$1" --get "$2" 2>/dev/null || true)
  [ "$actual" = "$3" ] || fail "expected $2=$3 got [$actual]"
}
config_absent() {
  if git config --file "$1" --get "$2" >/dev/null 2>&1; then fail "unexpected config $2"; fi
}
clean() { [ -z "$(git -C "$1" status --porcelain)" ] || fail "dirty checkout: $1"; }
create_source() {
  local path=$1 provider=$2 branch
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name 'Test User'
  git -C "$path" config user.email 'test@example.com'
  printf '{"name":"example/site"}\n' > "$path/composer.json"
  case "$provider" in
    lando) printf 'name: example-site\nrecipe: pantheon\n' > "$path/.lando.yml" ;;
    ddev)
      mkdir -p "$path/.ddev/providers"
      printf 'name: example-ddev\ntype: drupal11\n' > "$path/.ddev/config.yaml"
      printf '# Pantheon provider\n' > "$path/.ddev/providers/pantheon.yaml"
      ;;
  esac
  git -C "$path" add .
  git -C "$path" commit -qm 'Create fixture'
  for branch in feature1 feature2 feature3 feature4 feature5; do
    git -C "$path" branch "$branch"
  done
}
create_source "$MOCK_GIT_URL" lando
create_source "$TMP/source-ddev" ddev

cat > "$MOCK_BIN/terminus" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'terminus|%s\n' "$*" >> "$MOCK_TERMINUS_LOG"
case "${1:-}" in
  auth:whoami) echo developer@example.com ;;
  site:info) echo 'Example Org' ;;
  tag:list) echo 'Unmapped Group' ;;
  connection:info)
    [ "${3:-}" = '--field=git_url' ] || exit 2
    echo "$MOCK_GIT_URL"
    ;;
  *) echo "unexpected terminus $*" >&2; exit 2 ;;
esac
MOCK
for provider in lando ddev; do
  cat > "$MOCK_BIN/$provider" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
provider=${0##*/}
case "${1:-}" in
  info) echo '["https://example-runtime.test"]'; exit 0 ;;
  describe) echo '{"raw":{"primary_url":"https://example-ddev.test"}}'; exit 0 ;;
esac
line="$PWD|$provider"
for arg in "$@"; do line="$line|$arg"; done
printf '%s\n' "$line" >> "$MOCK_LOG"
if [ -n "${MOCK_FAIL_MATCH:-}" ]; then
  case "$line" in *"$MOCK_FAIL_MATCH"*) exit 9 ;; esac
fi
MOCK
done
chmod +x "$MOCK_BIN/"*
export PATH="$MOCK_BIN:$PATH"

bash "$CLI" config set root "$ROOT"
bash "$CLI" config set provider lando

# Planning never creates a checkout, starts a provider, or imports data.
: > "$TMP/nav-destination"
dry=$(PANTHEON_LOCAL_CHDIR_FILE="$TMP/nav-destination" bash "$CLI" multidev example-site.feature1 --dry-run --setup)
contains "$dry" 'Opt-in Drupal setup plan'
contains "$dry" 'initial local import from feature1'
[ ! -e "$ROOT/multidev/example-site-feature1" ] || fail 'dry-run cloned a checkout'
[ ! -s "$TMP/nav-destination" ] || fail 'dry-run emitted a shell navigation destination'
[ ! -s "$MOCK_LOG" ] || fail 'dry-run executed provider'
live_dry=$(bash "$CLI" multidev example-site.feature2 --dry-run --setup --database-source live)
contains "$live_dry" 'initial local import from live'
[ ! -e "$ROOT/multidev/example-site-feature2" ] || fail 'dry-run created a checkout'

# Unsafe/incompatible flag combinations fail before contacting Pantheon.
n=$(wc -l < "$MOCK_TERMINUS_LOG")
if bash "$CLI" multidev example-site.feature1 --database-source live >/dev/null 2>&1; then fail 'source without --setup'; fi
if bash "$CLI" multidev example-site.feature1 --setup --database-source ../../live >/dev/null 2>&1; then fail 'invalid source'; fi
if bash "$CLI" multidev example-site.feature1 --setup --database-source '' >/dev/null 2>&1; then fail 'empty source'; fi
if bash "$CLI" multidev example-site.feature1 --setup --start --dry-run >/dev/null 2>&1; then fail 'start with dry-run'; fi
[ "$(wc -l < "$MOCK_TERMINUS_LOG")" -eq "$n" ] || fail 'invalid input contacted Pantheon'

# Standard --setup performs the existing five-step setup exactly once in the
# newly created checkout. Record DB source separately from checkout identity.
output=$(PANTHEON_LOCAL_CHDIR_FILE="$TMP/nav-destination" bash "$CLI" multidev example-site.feature1 --setup)
DEST="$ROOT/multidev/example-site-feature1"
NAV_DEST=''
IFS= read -r -d '' NAV_DEST < "$TMP/nav-destination" || fail 'missing NUL-delimited successful navigation result'
[ "$NAV_DEST" = "$DEST" ] || fail 'navigation result differs from exact new checkout directory'
STATE="$DEST/.git/pantheon-local-tools/state"
contains "$output" 'Drupal bootstrap complete'
line_is "$MOCK_LOG" 1 "$DEST|lando|start"
line_is "$MOCK_LOG" 2 "$DEST|lando|composer|install"
line_is "$MOCK_LOG" 3 "$DEST|lando|pull|--code=none|--database=feature1|--files=none"
line_is "$MOCK_LOG" 4 "$DEST|lando|drush|updb|-y"
line_is "$MOCK_LOG" 5 "$DEST|lando|drush|cr"
[ "$(wc -l < "$MOCK_LOG")" -eq 5 ] || fail 'unexpected extra operations'
config_is "$STATE" pantheon.environment feature1
config_is "$STATE" data.database-source feature1
config_absent "$STATE" data.files-source
config_is "$STATE" bootstrap.status complete
config_is "$STATE" bootstrap.environment feature1
config_is "$STATE" workflow.setup.status complete
config_is "$STATE" local.url https://example-runtime.test
[ -f "$DEST/.lando.local.yml" ] || fail 'missing local override'
clean "$DEST"
if bash "$CLI" multidev example-site.feature1 --setup >/dev/null 2>&1; then fail 'duplicate checkout allowed'; fi
[ "$(wc -l < "$MOCK_LOG")" -eq 5 ] || fail 'duplicate checkout retried provider'

# Explicit Live DB source changes only the local database. --start with --setup
# invokes the provider start once instead of performing two start operations.
: > "$MOCK_LOG"
output=$(bash "$CLI" multidev example-site.feature2 --setup --start --database-source live)
LIVE="$ROOT/multidev/example-site-feature2"
LIVE_STATE="$LIVE/.git/pantheon-local-tools/state"
contains "$output" 'initial local import from live'
line_is "$MOCK_LOG" 1 "$LIVE|lando|start"
line_is "$MOCK_LOG" 2 "$LIVE|lando|composer|install"
line_is "$MOCK_LOG" 3 "$LIVE|lando|pull|--code=none|--database=live|--files=none"
[ "$(wc -l < "$MOCK_LOG")" -eq 5 ] || fail 'double start or unexpected commands'
config_is "$LIVE_STATE" pantheon.environment feature2
config_is "$LIVE_STATE" data.database-source live
config_is "$LIVE_STATE" bootstrap.environment feature2
config_absent "$LIVE_STATE" data.files-source
clean "$LIVE"

# A failed import leaves the checkout and failed phase intact; no Drush, retry,
# or automatic cleanup of the source tree occurs.
: > "$MOCK_LOG"
export MOCK_FAIL_MATCH='|lando|pull|'
: > "$TMP/nav-destination"
if PANTHEON_LOCAL_CHDIR_FILE="$TMP/nav-destination" bash "$CLI" multidev example-site.feature3 --setup --database-source test > "$TMP/fail.out" 2>&1; then fail 'pull failure ignored'; fi
[ ! -s "$TMP/nav-destination" ] || fail 'failed setup emitted a navigation result'
MOCK_FAIL_MATCH=''
FAILED="$ROOT/multidev/example-site-feature3"
FAILED_STATE="$FAILED/.git/pantheon-local-tools/state"
[ -d "$FAILED/.git" ] || fail 'failed setup deleted checkout'
grep -F 'checkout retained at' "$TMP/fail.out" >/dev/null || fail 'failure missing recovery location'
line_is "$MOCK_LOG" 3 "$FAILED|lando|pull|--code=none|--database=test|--files=none"
[ "$(wc -l < "$MOCK_LOG")" -eq 3 ] || fail 'continued after pull failure'
config_is "$FAILED_STATE" bootstrap.status failed
config_is "$FAILED_STATE" bootstrap.step database-pull
config_is "$FAILED_STATE" bootstrap.environment feature3
config_absent "$FAILED_STATE" data.database-source
clean "$FAILED"
if bash "$CLI" multidev example-site.feature3 --setup >/dev/null 2>&1; then fail 're-cloned failed checkout'; fi
[ "$(wc -l < "$MOCK_LOG")" -eq 3 ] || fail 'duplicate retry executed provider'

# Composer failure retains the local checkout without a database import.
: > "$MOCK_LOG"
export MOCK_FAIL_MATCH='|lando|composer|install'
if bash "$CLI" multidev example-site.feature4 --setup >/dev/null 2>&1; then fail 'Composer failure ignored'; fi
MOCK_FAIL_MATCH=''
COMPOSER_FAIL="$ROOT/multidev/example-site-feature4"
config_is "$COMPOSER_FAIL/.git/pantheon-local-tools/state" bootstrap.step composer-install
[ "$(wc -l < "$MOCK_LOG")" -eq 2 ] || fail 'continued after Composer failure'
clean "$COMPOSER_FAIL"

# DDEV delegates to its existing provider-specific Composer and DB-only pull.
export MOCK_GIT_URL="$TMP/source-ddev"
: > "$MOCK_LOG"
output=$(bash "$CLI" multidev example-ddev.feature5 --provider ddev --setup --database-source live)
DDEV="$ROOT/multidev/example-ddev-feature5"
DDEV_STATE="$DDEV/.git/pantheon-local-tools/state"
contains "$output" 'Drupal bootstrap complete'
line_is "$MOCK_LOG" 1 "$DDEV|ddev|start"
line_is "$MOCK_LOG" 2 "$DDEV|ddev|composer|install"
line_is "$MOCK_LOG" 3 "$DDEV|ddev|pull|pantheon|--environment=DDEV_PANTHEON_SITE=example-ddev,DDEV_PANTHEON_ENVIRONMENT=live|--skip-files|-y"
line_is "$MOCK_LOG" 4 "$DDEV|ddev|drush|updb|-y"
line_is "$MOCK_LOG" 5 "$DDEV|ddev|drush|cr"
config_is "$DDEV_STATE" pantheon.environment feature5
config_is "$DDEV_STATE" data.database-source live
config_absent "$DDEV_STATE" data.files-source
config_is "$DDEV_STATE" bootstrap.status complete
config_is "$DDEV_STATE" local.url https://example-ddev.test
clean "$DDEV"

# Never implicitly create or mutate Pantheon environments, pull Git/files,
# or rebuild containers.
if grep -E 'multidev:create|env:delete|deploy' "$MOCK_TERMINUS_LOG" >/dev/null; then fail 'unexpected remote mutation'; fi
if grep -E '\|rebuild|\|--code=(live|test|feature)|\|--files=(live|test|feature)' "$MOCK_LOG" >/dev/null; then fail 'unexpected local data or provider mutation'; fi
printf 'multidev setup composition tests passed\n'
