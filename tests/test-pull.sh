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

# Lando receives explicit data sources and an explicit code=none guard.
LANDO="$TMP_ROOT/lando"
create_repo "$LANDO" lando
mkdir -p "$LANDO/subdir" "$LANDO/.git/pantheon-local-tools"
LANDO_STATE=$(state_path "$LANDO")
git config --file "$LANDO_STATE" pantheon.site example-site
git config --file "$LANDO_STATE" local.provider lando

lando_output=$(cd "$LANDO/subdir" && bash "$CLI" pull live)
assert_contains "$lando_output" 'Environment: live'
assert_contains "$lando_output" 'Provider:    lando'
assert_contains "$lando_output" 'Git code:    unchanged'
assert_file_contains "$MOCK_LOG" 'lando|pull|--code=none|--database=live|--files=live'
[ "$(git config --file "$LANDO_STATE" --get data.source)" = live ] || fail 'Lando data source was not recorded'
assert_contains "$(cd "$LANDO" && bash "$CLI" status)" 'Data source:     live'

# DDEV gets a one-time Pantheon site/environment override without rewriting project config.
DDEV="$TMP_ROOT/ddev"
create_repo "$DDEV" ddev
mkdir -p "$DDEV/.git/pantheon-local-tools"
DDEV_STATE=$(state_path "$DDEV")
git config --file "$DDEV_STATE" pantheon.site example-site
git config --file "$DDEV_STATE" local.provider ddev

bash "$CLI" pull --help >/dev/null
(cd "$DDEV" && bash "$CLI" pull test >/dev/null)
assert_file_contains "$MOCK_LOG" 'ddev|pull|pantheon|--environment=DDEV_PANTHEON_SITE=example-site,DDEV_PANTHEON_ENVIRONMENT=test|-y'
[ "$(git config --file "$DDEV_STATE" --get data.source)" = test ] || fail 'DDEV data source was not recorded'

# An ordinary DDEV checkout can rely on its own configured site while we override only ENV.
DDEV_UNMANAGED="$TMP_ROOT/ddev-unmanaged"
create_repo "$DDEV_UNMANAGED" ddev
(cd "$DDEV_UNMANAGED" && bash "$CLI" pull dev >/dev/null)
DDEV_UNMANAGED_STATE=$(state_path "$DDEV_UNMANAGED")
assert_file_contains "$MOCK_LOG" 'ddev|pull|pantheon|--environment=DDEV_PANTHEON_ENVIRONMENT=dev|-y'
[ "$(git config --file "$DDEV_UNMANAGED_STATE" --get local.provider)" = ddev ] || fail 'detected DDEV provider was not recorded'
[ "$(git config --file "$DDEV_UNMANAGED_STATE" --get data.source)" = dev ] || fail 'unmanaged DDEV data source was not recorded'

# Ambiguous provider configuration must fail unless the user chooses one explicitly.
AMBIG="$TMP_ROOT/ambiguous"
create_repo "$AMBIG" both
if (cd "$AMBIG" && bash "$CLI" pull live >/dev/null 2>&1); then
  fail 'ambiguous provider configuration was accepted'
fi
(cd "$AMBIG" && bash "$CLI" pull live --provider lando >/dev/null)
assert_contains "$(cd "$AMBIG" && bash "$CLI" status)" 'Data source:     live'

# Provider failures do not create successful provenance.
FAILED="$TMP_ROOT/failed"
create_repo "$FAILED" lando
export MOCK_PROVIDER_FAIL=lando
if (cd "$FAILED" && bash "$CLI" pull live >/dev/null 2>&1); then
  fail 'failed provider pull unexpectedly succeeded'
fi
unset MOCK_PROVIDER_FAIL
FAILED_STATE=$(state_path "$FAILED")
if [ -f "$FAILED_STATE" ] && git config --file "$FAILED_STATE" --get data.source >/dev/null 2>&1; then
  fail 'failed provider pull recorded a data source'
fi

# If a delegated provider changes tracked code, fail and do not record provenance.
MUTATED="$TMP_ROOT/mutated"
create_repo "$MUTATED" lando
export MOCK_MUTATE_TRACKED=true
if (cd "$MUTATED" && bash "$CLI" pull live >/dev/null 2>&1); then
  fail 'tracked provider mutation was not detected'
fi
unset MOCK_MUTATE_TRACKED
MUTATED_STATE=$(state_path "$MUTATED")
if [ -f "$MUTATED_STATE" ] && git config --file "$MUTATED_STATE" --get data.source >/dev/null 2>&1; then
  fail 'tracked mutation recorded a data source'
fi

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
