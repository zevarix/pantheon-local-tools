#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
export HOME="$TMP_ROOT/home"
export PANTHEON_LOCAL_CONFIG="$TMP_ROOT/config/pantheon-local-tools/config"
mkdir -p "$HOME"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "expected output not to contain [$2], got [$1]" ;; *) ;; esac; }

# Profile properties extend, rather than replace, the existing Tag route contract.
bash "$CLI" config tag set 'Client Sites.v2' 'clients/main'
assert_eq "$(bash "$CLI" config tag get 'Client Sites.v2')" 'clients/main'
assert_contains "$(bash "$CLI" config tag list)" 'Client Sites.v2=clients/main'

bash "$CLI" config tag profile set 'Client Sites.v2' config-strategy full-export
bash "$CLI" config tag profile set 'Client Sites.v2' config-path config/sync
assert_eq "$(bash "$CLI" config tag profile get 'Client Sites.v2' config-strategy)" 'full-export'
assert_eq "$(bash "$CLI" config tag profile get 'Client Sites.v2' config-path)" 'config/sync'

profile=$(bash "$CLI" config tag profile list 'Client Sites.v2')
assert_contains "$profile" 'config-strategy=full-export'
assert_contains "$profile" 'config-path=config/sync'

all_profiles=$(bash "$CLI" config tag profile list)
assert_contains "$all_profiles" 'Client Sites.v2.config-strategy=full-export'
assert_contains "$all_profiles" 'Client Sites.v2.config-path=config/sync'

config_output=$(bash "$CLI" config list)
assert_contains "$config_output" 'tag.Client Sites.v2=clients/main'
assert_contains "$config_output" 'tag.Client Sites.v2.config-strategy=full-export'
assert_contains "$config_output" 'tag.Client Sites.v2.config-path=config/sync'

# Strategy validation is closed over the deliberately small initial vocabulary.
if bash "$CLI" config tag profile set 'Client Sites.v2' config-strategy search-api >/dev/null 2>&1; then
  fail 'unknown config strategy was accepted'
fi
assert_eq "$(bash "$CLI" config tag profile get 'Client Sites.v2' config-strategy)" 'full-export'

bash "$CLI" config tag profile set 'Client Sites.v2' config-strategy overlay-delta
assert_eq "$(bash "$CLI" config tag profile get 'Client Sites.v2' config-strategy)" 'overlay-delta'

# Config paths are project-relative and reject escape/portability hazards.
bash "$CLI" config tag profile set 'Client Sites.v2' config-path config/site-overrides
assert_eq "$(bash "$CLI" config tag profile get 'Client Sites.v2' config-path)" 'config/site-overrides'
tilde_path='~/config'
for invalid_path in \
  '/absolute/path' \
  '../escape' \
  'config/../escape' \
  'config//sync' \
  'config/sync/' \
  "$tilde_path" \
  'config\\sync'
do
  if bash "$CLI" config tag profile set 'Client Sites.v2' config-path "$invalid_path" >/dev/null 2>&1; then
    fail "invalid config-path was accepted: $invalid_path"
  fi
done
assert_eq "$(bash "$CLI" config tag profile get 'Client Sites.v2' config-path)" 'config/site-overrides'

# Profile properties cannot create a new routing identity implicitly.
if bash "$CLI" config tag profile set 'Missing Group' config-strategy full-export >/dev/null 2>&1; then
  fail 'profile setting unexpectedly created or accepted a missing Tag route'
fi
assert_not_contains "$(bash "$CLI" config tag list)" 'Missing Group='

# Individual properties are optional and may be removed independently.
bash "$CLI" config tag profile unset 'Client Sites.v2' config-path
if bash "$CLI" config tag profile get 'Client Sites.v2' config-path >/dev/null 2>&1; then
  fail 'unset config-path still resolves'
fi
assert_not_contains "$(bash "$CLI" config tag profile list 'Client Sites.v2')" 'config-path='
assert_eq "$(bash "$CLI" config tag profile get 'Client Sites.v2' config-strategy)" 'overlay-delta'

# Hand-edited malformed profile values fail closed when read or listed.
git config --file "$PANTHEON_LOCAL_CONFIG" --replace-all 'tag.Client Sites.v2.config-strategy' 'mystery'
if bash "$CLI" config tag profile get 'Client Sites.v2' config-strategy >/dev/null 2>&1; then
  fail 'malformed stored config-strategy was accepted by profile get'
fi
if bash "$CLI" config tag profile list 'Client Sites.v2' >/dev/null 2>&1; then
  fail 'malformed stored config-strategy was accepted by profile list'
fi
if bash "$CLI" config list >/dev/null 2>&1; then
  fail 'malformed stored config-strategy was accepted by config list'
fi
git config --file "$PANTHEON_LOCAL_CONFIG" --replace-all 'tag.Client Sites.v2.config-strategy' 'full-export'

# Removing a legacy Tag route also removes its associated profile state.
bash "$CLI" config tag profile set 'Client Sites.v2' config-path config/sync
bash "$CLI" config tag unset 'Client Sites.v2'
assert_eq "$(bash "$CLI" config tag list)" ''
for key in \
  'tag.Client Sites.v2.directory' \
  'tag.Client Sites.v2.config-strategy' \
  'tag.Client Sites.v2.config-path'
do
  if git config --file "$PANTHEON_LOCAL_CONFIG" --get "$key" >/dev/null 2>&1; then
    fail "tag unset left stale config key: $key"
  fi
done

# The documented example stays valid Git config and includes both supported strategies.
assert_eq "$(git config --file "$REPO_ROOT/config.example" --get 'tag.Full Export Example.config-strategy')" 'full-export'
assert_eq "$(git config --file "$REPO_ROOT/config.example" --get 'tag.Full Export Example.config-path')" 'config/sync'
assert_eq "$(git config --file "$REPO_ROOT/config.example" --get 'tag.Protected Overlay Example.config-strategy')" 'overlay-delta'
assert_eq "$(git config --file "$REPO_ROOT/config.example" --get 'tag.Protected Overlay Example.config-path')" 'config/site-overrides'

printf 'config profile tests passed\n'
