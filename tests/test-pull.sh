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
{
  printf 'lando'
  for arg in "$@"; do printf '|%s' "$arg"; done
  printf '\n'
} >> "${MOCK_LOG:?}"
[ "${MOCK_PROVIDER_FAIL:-}" != lando ] || exit 9
if [ "${MOCK_MUTATE_TRACKED:-false}" = true ]; then
  printf 'provider mutation\n' >> README.md
fi
MOCK
chmod +x "$MOCK_BIN/lando"

cat > "$MOCK_BIN/ddev" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'ddev'
  for arg in "$@"; do printf '|%s' "$arg"; done
  printf '\n'
} >> "${MOCK_LOG:?}"
[ "${MOCK_PROVIDER_FAIL:-}" != ddev ] || exit 9
if [ "${MOCK_MUTATE_TRACKED:-false}" = true ]; then
  printf 'provider mutation\n' >> README.md
fi
MOCK
chmod +x "$MOCK_BIN/ddev"

export PATH="$MOCK_BIN:$PATH"
export MOCK_LOG

create_repo() {
  local path=$1 provider=$2
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name 'Test User'
  git -C "$path" config user.email 'test@example.com'
  printf 'fixture\n' > "$path/README.md"

  case "$provider" in
    lando)
      printf 'name: example-site\nrecipe: pantheon\n' > "$path/.lando.yml"
      ;;
    ddev)
      mkdir -p "$path/.ddev/providers"
      printf 'name: example-site\ntype: drupal11\n' > "$path/.ddev/config.yaml"
      printf '# Pantheon provider fixture\n' > "$path/.ddev/providers/pantheon.yaml"
      ;;
    both)
      printf 'name: example-site\nrecipe: pantheon\n' > "$path/.lando.yml"
      mkdir -p "$path/.ddev/providers"
      printf 'name: example-site\ntype: drupal11\n' > "$path/.ddev/config.yaml"
      printf '# Pantheon provider fixture\n' > "$path/.ddev/providers/pantheon.yaml"
      ;;
    *) fail "unknown provider fixture: $provider" ;;
  esac

  git -C "$path" add .
  git -C "$path" commit -qm 'Create pull fixture'
}

state_path() {
  printf '%s/.git/pantheon-local-tools/state\n' "$1"
}

assert_contains "$(bash "$CLI" --help)" 'pantheon-local pull ENV'
assert_contains "$(bash "$CLI" pull --help)" '--database-only'
assert_contains "$(bash "$CLI" pull --help)" '--files-only'

# Lando defaults to both database and files, never code.
LANDO="$TMP_ROOT/lando"
create_repo "$LANDO" lando
mkdir -p "$LANDO/subdir" "$LANDO/.git/pantheon-local-tools"
LANDO_STATE=$(state_path "$LANDO")
git config --file "$LANDO_STATE" pantheon.site example-site
git config --file "$LANDO_STATE" local.provider lando

lando_output=$(cd "$LANDO/subdir" && bash "$CLI" pull live)
assert_contains "$lando_output" 'Environment: live'
assert_contains "$lando_output" 'Components:  database, files'
assert_contains "$lando_output" 'Provider:    lando'
assert_contains "$lando_output" 'Git code:    unchanged'
assert_file_contains "$MOCK_LOG" 'lando|pull|--code=none|--database=live|--files=live'
assert_config "$LANDO_STATE" data.database-source live
assert_config "$LANDO_STATE" data.files-source live
status_output=$(cd "$LANDO" && bash "$CLI" status)
assert_contains "$status_output" 'Database source: live'
assert_contains "$status_output" 'Files source:    live'

# Database-only Lando pull changes only database provenance and explicitly skips files.
(cd "$LANDO" && bash "$CLI" pull test --database-only >/dev/null)
assert_file_contains "$MOCK_LOG" 'lando|pull|--code=none|--database=test|--files=none'
assert_config "$LANDO_STATE" data.database-source test
assert_config "$LANDO_STATE" data.files-source live

# Files-only Lando pull changes only files provenance and explicitly skips the database.
(cd "$LANDO" && bash "$CLI" pull dev --files-only >/dev/null)
assert_file_contains "$MOCK_LOG" 'lando|pull|--code=none|--database=none|--files=dev'
assert_config "$LANDO_STATE" data.database-source test
assert_config "$LANDO_STATE" data.files-source dev

# DDEV gets one-time Pantheon overrides and maps component selection to skip flags.
DDEV="$TMP_ROOT/ddev"
create_repo "$DDEV" ddev
mkdir -p "$DDEV/.git/pantheon-local-tools"
DDEV_STATE=$(state_path "$DDEV")
git config --file "$DDEV_STATE" pantheon.site example-site
git config --file "$DDEV_STATE" local.provider ddev

(cd "$DDEV" && bash "$CLI" pull test --database-only >/dev/null)
assert_file_contains "$MOCK_LOG" 'ddev|pull|pantheon|--environment=DDEV_PANTHEON_SITE=example-site,DDEV_PANTHEON_ENVIRONMENT=test|--skip-files|-y'
assert_config "$DDEV_STATE" data.database-source test
assert_config_missing "$DDEV_STATE" data.files-source

(cd "$DDEV" && bash "$CLI" pull live --files-only >/dev/null)
assert_file_contains "$MOCK_LOG" 'ddev|pull|pantheon|--environment=DDEV_PANTHEON_SITE=example-site,DDEV_PANTHEON_ENVIRONMENT=live|--skip-db|-y'
assert_config "$DDEV_STATE" data.database-source test
assert_config "$DDEV_STATE" data.files-source live

# An ordinary DDEV checkout can rely on its own configured site while ENV is overridden.
DDEV_UNMANAGED="$TMP_ROOT/ddev-unmanaged"
create_repo "$DDEV_UNMANAGED" ddev
(cd "$DDEV_UNMANAGED" && bash "$CLI" pull dev >/dev/null)
DDEV_UNMANAGED_STATE=$(state_path "$DDEV_UNMANAGED")
assert_file_contains "$MOCK_LOG" 'ddev|pull|pantheon|--environment=DDEV_PANTHEON_ENVIRONMENT=dev|-y'
assert_config "$DDEV_UNMANAGED_STATE" local.provider ddev
assert_config "$DDEV_UNMANAGED_STATE" data.database-source dev
assert_config "$DDEV_UNMANAGED_STATE" data.files-source dev

# Legacy single-source provenance migrates losslessly on the first component pull.
LEGACY="$TMP_ROOT/legacy"
create_repo "$LEGACY" lando
mkdir -p "$LEGACY/.git/pantheon-local-tools"
LEGACY_STATE=$(state_path "$LEGACY")
git config --file "$LEGACY_STATE" local.provider lando
git config --file "$LEGACY_STATE" data.source legacy-env
legacy_status=$(cd "$LEGACY" && bash "$CLI" status)
assert_contains "$legacy_status" 'Database source: legacy-env'
assert_contains "$legacy_status" 'Files source:    legacy-env'
(cd "$LEGACY" && bash "$CLI" pull fresh-db --database-only >/dev/null)
assert_config_missing "$LEGACY_STATE" data.source
assert_config "$LEGACY_STATE" data.database-source fresh-db
assert_config "$LEGACY_STATE" data.files-source legacy-env

# Ambiguous provider configuration must fail unless the user chooses one explicitly.
AMBIG="$TMP_ROOT/ambiguous"
create_repo "$AMBIG" both
if (cd "$AMBIG" && bash "$CLI" pull live >/dev/null 2>&1); then
  fail 'ambiguous provider configuration was accepted'
fi
(cd "$AMBIG" && bash "$CLI" pull live --provider lando >/dev/null)
AMBIG_STATUS=$(cd "$AMBIG" && bash "$CLI" status)
assert_contains "$AMBIG_STATUS" 'Database source: live'
assert_contains "$AMBIG_STATUS" 'Files source:    live'

# Component selectors are mutually exclusive.
if (cd "$LANDO" && bash "$CLI" pull live --database-only --files-only >/dev/null 2>&1); then
  fail 'database-only and files-only were accepted together'
fi

# Provider failures do not create successful provenance.
FAILED="$TMP_ROOT/failed"
create_repo "$FAILED" lando
export MOCK_PROVIDER_FAIL=lando
if (cd "$FAILED" && bash "$CLI" pull live >/dev/null 2>&1); then
  fail 'failed provider pull unexpectedly succeeded'
fi
unset MOCK_PROVIDER_FAIL
FAILED_STATE=$(state_path "$FAILED")
assert_config_missing "$FAILED_STATE" data.database-source
assert_config_missing "$FAILED_STATE" data.files-source

# If a delegated provider changes tracked code, fail and do not record provenance.
MUTATED="$TMP_ROOT/mutated"
create_repo "$MUTATED" lando
export MOCK_MUTATE_TRACKED=true
if (cd "$MUTATED" && bash "$CLI" pull live >/dev/null 2>&1); then
  fail 'tracked provider mutation was not detected'
fi
unset MOCK_MUTATE_TRACKED
MUTATED_STATE=$(state_path "$MUTATED")
assert_config_missing "$MUTATED_STATE" data.database-source
assert_config_missing "$MUTATED_STATE" data.files-source

# DDEV requires the Pantheon provider integration to exist.
DDEV_MISSING="$TMP_ROOT/ddev-missing-provider"
create_repo "$DDEV_MISSING" ddev
rm "$DDEV_MISSING/.ddev/providers/pantheon.yaml"
if (cd "$DDEV_MISSING" && bash "$CLI" pull live >/dev/null 2>&1); then
  fail 'DDEV pull succeeded without Pantheon provider integration'
fi

if (cd "$LANDO" && bash "$CLI" pull 'bad.env' >/dev/null 2>&1); then
  fail 'invalid Pantheon environment was accepted'
fi

printf 'pull tests passed\n'
