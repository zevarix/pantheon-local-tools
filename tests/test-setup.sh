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
assert_config() {
  local file=$1 key=$2 expected=$3 actual
  actual=$(git config --file "$file" --get "$key" 2>/dev/null || true)
  [ "$actual" = "$expected" ] || fail "expected $key=$expected in $file, got [$actual]"
}
assert_config_missing() {
  local file=$1 key=$2
  if [ -f "$file" ] && git config --file "$file" --get "$key" >/dev/null 2>&1; then
    fail "expected $key to be absent from $file"
  fi
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
MOCK
chmod +x "$MOCK_BIN/ddev"

export PATH="$MOCK_BIN:$PATH"
export MOCK_LOG

create_repo() {
  local path=$1 provider=$2 env=$3
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name 'Test User'
  git -C "$path" config user.email 'test@example.com'
  printf 'fixture\n' > "$path/README.md"
  printf '{"name":"example/site"}\n' > "$path/composer.json"

  case "$provider" in
    lando)
      printf 'name: example-site\nrecipe: pantheon\n' > "$path/.lando.yml"
      ;;
    ddev)
      mkdir -p "$path/.ddev/providers"
      printf 'name: example-site\ntype: drupal11\n' > "$path/.ddev/config.yaml"
      printf '# Pantheon provider fixture\n' > "$path/.ddev/providers/pantheon.yaml"
      ;;
    *) fail "unknown provider fixture: $provider" ;;
  esac

  git -C "$path" add .
  git -C "$path" commit -qm 'Create setup fixture'
  git -C "$path" branch -M misleading-branch

  mkdir -p "$path/.git/pantheon-local-tools"
  git config --file "$path/.git/pantheon-local-tools/state" pantheon.site example-site
  git config --file "$path/.git/pantheon-local-tools/state" pantheon.environment "$env"
  git config --file "$path/.git/pantheon-local-tools/state" local.provider "$provider"
}

state_path() {
  printf '%s/.git/pantheon-local-tools/state\n' "$1"
}

reset_log() {
  : > "$MOCK_LOG"
}

assert_contains "$(bash "$CLI" --help)" 'pantheon-local setup [--provider ddev|lando] [--dry-run]'
setup_help=$(bash "$CLI" setup --help)
assert_contains "$setup_help" 'provider-owned composer install'
assert_contains "$setup_help" 'replaces local database data'
assert_contains "$setup_help" 'stops on the first failed step'
assert_contains "$setup_help" 'checkout-local PLT state'
assert_contains "$setup_help" 'Fix the reported failure and run pantheon-local setup again.'

# Dry-run validates and reports the exact managed environment without any mutation.
DRY="$TMP_ROOT/dry"
create_repo "$DRY" lando phase1
DRY_STATE=$(state_path "$DRY")
rm -f "$MOCK_LOG"
dry_output=$(cd "$DRY" && bash "$CLI" setup --dry-run)
assert_contains "$dry_output" 'Pantheon:    example-site.phase1'
assert_contains "$dry_output" 'lando pull phase1 --database-only --provider lando'
assert_contains "$dry_output" 'Dry-run only:'
[ ! -e "$MOCK_LOG" ] || fail 'dry-run executed a provider command'
assert_config_missing "$DRY_STATE" bootstrap.status
assert_config_missing "$DRY_STATE" data.database-source

# Lando happy path follows the required order and pulls the recorded environment, not the branch.
LANDO="$TMP_ROOT/lando"
create_repo "$LANDO" lando phase1
LANDO_STATE=$(state_path "$LANDO")
reset_log
lando_output=$(cd "$LANDO" && bash "$CLI" setup)
assert_line "$MOCK_LOG" 1 'lando|start'
assert_line "$MOCK_LOG" 2 'lando|composer|install'
assert_line "$MOCK_LOG" 3 'lando|pull|--code=none|--database=phase1|--files=none'
assert_line "$MOCK_LOG" 4 'lando|drush|updb|-y'
assert_line "$MOCK_LOG" 5 'lando|drush|cr'
assert_contains "$lando_output" 'Drupal bootstrap complete'
assert_contains "$lando_output" 'Environment: phase1'
assert_config "$LANDO_STATE" data.database-source phase1
assert_config_missing "$LANDO_STATE" data.files-source
assert_config "$LANDO_STATE" bootstrap.status complete
assert_config "$LANDO_STATE" bootstrap.step complete
assert_config "$LANDO_STATE" bootstrap.environment phase1
assert_config "$LANDO_STATE" bootstrap.provider lando
[ -n "$(git config --file "$LANDO_STATE" --get bootstrap.updated-at)" ] || fail 'bootstrap timestamp was not recorded'
status_output=$(cd "$LANDO" && bash "$CLI" status)
assert_contains "$status_output" 'Bootstrap status:  complete'
assert_contains "$status_output" 'Bootstrap step:    complete'

# DDEV uses DDEV-owned Composer/Drush and the existing Pantheon database-only pull contract.
DDEV="$TMP_ROOT/ddev"
create_repo "$DDEV" ddev feature1
DDEV_STATE=$(state_path "$DDEV")
reset_log
(cd "$DDEV" && bash "$CLI" setup >/dev/null)
assert_line "$MOCK_LOG" 1 'ddev|start'
assert_line "$MOCK_LOG" 2 'ddev|composer|install'
assert_line "$MOCK_LOG" 3 'ddev|pull|pantheon|--environment=DDEV_PANTHEON_SITE=example-site,DDEV_PANTHEON_ENVIRONMENT=feature1|--skip-files|-y'
assert_line "$MOCK_LOG" 4 'ddev|drush|updb|-y'
assert_line "$MOCK_LOG" 5 'ddev|drush|cr'
assert_config "$DDEV_STATE" data.database-source feature1
assert_config_missing "$DDEV_STATE" data.files-source
assert_config "$DDEV_STATE" bootstrap.status complete

# Known preflight failures happen before the provider starts.
UNMANAGED="$TMP_ROOT/unmanaged"
create_repo "$UNMANAGED" lando feature2
rm -rf "$UNMANAGED/.git/pantheon-local-tools"
reset_log
if (cd "$UNMANAGED" && bash "$CLI" setup >/dev/null 2>&1); then
  fail 'setup accepted a checkout without recorded Pantheon environment state'
fi
[ ! -s "$MOCK_LOG" ] || fail 'unmanaged checkout failure started the provider'

DDEV_MISSING="$TMP_ROOT/ddev-missing"
create_repo "$DDEV_MISSING" ddev feature3
rm "$DDEV_MISSING/.ddev/providers/pantheon.yaml"
reset_log
if (cd "$DDEV_MISSING" && bash "$CLI" setup >/dev/null 2>&1); then
  fail 'setup accepted DDEV without the Pantheon provider integration'
fi
[ ! -s "$MOCK_LOG" ] || fail 'missing DDEV Pantheon integration started the provider'

COMPOSER_MISSING="$TMP_ROOT/composer-missing"
create_repo "$COMPOSER_MISSING" lando feature4
rm "$COMPOSER_MISSING/composer.json"
reset_log
if (cd "$COMPOSER_MISSING" && bash "$CLI" setup >/dev/null 2>&1); then
  fail 'setup accepted a checkout without composer.json'
fi
[ ! -s "$MOCK_LOG" ] || fail 'missing composer.json started the provider'

# Every mutating failure records the exact failed step and prevents later steps.
START_FAIL="$TMP_ROOT/start-fail"
create_repo "$START_FAIL" lando fail1
START_STATE=$(state_path "$START_FAIL")
reset_log
export MOCK_FAIL_MATCH='lando|start'
if (cd "$START_FAIL" && bash "$CLI" setup >/dev/null 2>&1); then fail 'provider start failure unexpectedly succeeded'; fi
unset MOCK_FAIL_MATCH
assert_line "$MOCK_LOG" 1 'lando|start'
assert_file_not_contains "$MOCK_LOG" 'lando|composer|install'
assert_config "$START_STATE" bootstrap.status failed
assert_config "$START_STATE" bootstrap.step provider-start
assert_config_missing "$START_STATE" data.database-source

COMPOSER_FAIL="$TMP_ROOT/composer-fail"
create_repo "$COMPOSER_FAIL" lando fail2
COMPOSER_STATE=$(state_path "$COMPOSER_FAIL")
reset_log
export MOCK_FAIL_MATCH='lando|composer|install'
if (cd "$COMPOSER_FAIL" && bash "$CLI" setup >/dev/null 2>&1); then fail 'Composer failure unexpectedly succeeded'; fi
unset MOCK_FAIL_MATCH
assert_file_contains "$MOCK_LOG" 'lando|start'
assert_file_contains "$MOCK_LOG" 'lando|composer|install'
assert_file_not_contains "$MOCK_LOG" 'lando|pull|'
assert_file_not_contains "$MOCK_LOG" 'lando|drush|updb|-y'
assert_config "$COMPOSER_STATE" bootstrap.status failed
assert_config "$COMPOSER_STATE" bootstrap.step composer-install
assert_config_missing "$COMPOSER_STATE" data.database-source

PULL_FAIL="$TMP_ROOT/pull-fail"
create_repo "$PULL_FAIL" lando fail3
PULL_STATE=$(state_path "$PULL_FAIL")
reset_log
export MOCK_FAIL_MATCH='lando|pull|'
if (cd "$PULL_FAIL" && bash "$CLI" setup >/dev/null 2>&1); then fail 'database pull failure unexpectedly succeeded'; fi
unset MOCK_FAIL_MATCH
assert_file_contains "$MOCK_LOG" 'lando|pull|--code=none|--database=fail3|--files=none'
assert_file_not_contains "$MOCK_LOG" 'lando|drush|updb|-y'
assert_file_not_contains "$MOCK_LOG" 'lando|drush|cr'
assert_config "$PULL_STATE" bootstrap.status failed
assert_config "$PULL_STATE" bootstrap.step database-pull
assert_config_missing "$PULL_STATE" data.database-source

UPDB_FAIL="$TMP_ROOT/updb-fail"
create_repo "$UPDB_FAIL" lando fail4
UPDB_STATE=$(state_path "$UPDB_FAIL")
reset_log
export MOCK_FAIL_MATCH='lando|drush|updb|-y'
if (cd "$UPDB_FAIL" && bash "$CLI" setup >/dev/null 2>&1); then fail 'updb failure unexpectedly succeeded'; fi
unset MOCK_FAIL_MATCH
assert_file_contains "$MOCK_LOG" 'lando|drush|updb|-y'
assert_file_not_contains "$MOCK_LOG" 'lando|drush|cr'
assert_config "$UPDB_STATE" data.database-source fail4
assert_config "$UPDB_STATE" bootstrap.status failed
assert_config "$UPDB_STATE" bootstrap.step drush-updb

CR_FAIL="$TMP_ROOT/cr-fail"
create_repo "$CR_FAIL" lando fail5
CR_STATE=$(state_path "$CR_FAIL")
reset_log
export MOCK_FAIL_MATCH='lando|drush|cr'
if (cd "$CR_FAIL" && bash "$CLI" setup >/dev/null 2>&1); then fail 'cache rebuild failure unexpectedly succeeded'; fi
unset MOCK_FAIL_MATCH
assert_file_contains "$MOCK_LOG" 'lando|drush|updb|-y'
assert_file_contains "$MOCK_LOG" 'lando|drush|cr'
assert_config "$CR_STATE" data.database-source fail5
assert_config "$CR_STATE" bootstrap.status failed
assert_config "$CR_STATE" bootstrap.step drush-cr

printf 'setup tests passed\n'
