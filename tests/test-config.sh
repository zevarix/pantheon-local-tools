#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
export HOME="$TMP_ROOT/home"
export PANTHEON_LOCAL_CONFIG="$TMP_ROOT/config/pantheon-local-tools/config"
mkdir -p "$HOME"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }

# The documented example must remain valid Git config data, not executable shell.
assert_eq "$(git config --file "$REPO_ROOT/config.example" --get local.provider)" 'auto'
if grep -Eq '(^|[[:space:]])(declare|source|eval)[[:space:]]' "$REPO_ROOT/config.example"; then
  fail 'config.example contains executable shell syntax'
fi

assert_eq "$(bash "$CLI" config path)" "$PANTHEON_LOCAL_CONFIG"
assert_eq "$(bash "$CLI" config get provider)" 'auto'
assert_eq "$(bash "$CLI" config get root)" "$HOME/sites/pantheon"

bash "$CLI" config set root '~/Pantheon Sites'
assert_eq "$(bash "$CLI" config get root)" "$HOME/Pantheon Sites"

# WSL uses Linux paths; /mnt/<drive>/... is accepted while native Windows paths are rejected.
bash "$CLI" config set root '/mnt/c/Users/example/Pantheon Sites'
assert_eq "$(bash "$CLI" config get root)" '/mnt/c/Users/example/Pantheon Sites'
if bash "$CLI" config set root 'C:\Users\example\Pantheon' >/dev/null 2>&1; then
  fail 'native Windows root path was accepted'
fi
if bash "$CLI" config set root 'relative/path' >/dev/null 2>&1; then
  fail 'relative root path was accepted'
fi

bash "$CLI" config set root "$HOME/Pantheon Sites"
bash "$CLI" config set provider lando
assert_eq "$(bash "$CLI" config get provider)" 'lando'
if bash "$CLI" config set provider nope >/dev/null 2>&1; then fail 'invalid provider was accepted'; fi

bash "$CLI" config set site-prefix example
assert_eq "$(bash "$CLI" config get site-prefix)" 'example'

bash "$CLI" config tag set 'Client Sites.v2' 'clients/main'
assert_eq "$(bash "$CLI" config tag get 'Client Sites.v2')" 'clients/main'
assert_contains "$(bash "$CLI" config tag list)" 'Client Sites.v2=clients/main'

if bash "$CLI" config tag set Unsafe '/absolute/path' >/dev/null 2>&1; then fail 'absolute tag directory was accepted'; fi
if bash "$CLI" config tag set Unsafe '../escape' >/dev/null 2>&1; then fail '.. tag directory was accepted'; fi
if bash "$CLI" config tag set Unsafe 'foo\\bar' >/dev/null 2>&1; then fail 'backslash tag directory was accepted'; fi

output=$(bash "$CLI" config list)
assert_contains "$output" "root=$HOME/Pantheon Sites"
assert_contains "$output" 'provider=lando'
assert_contains "$output" 'site-prefix=example'
assert_contains "$output" 'tag.Client Sites.v2=clients/main'

bash "$CLI" config unset provider
assert_eq "$(bash "$CLI" config get provider)" 'auto'
bash "$CLI" config tag unset 'Client Sites.v2'
assert_eq "$(bash "$CLI" config tag list)" ''

printf 'config tests passed\n'
