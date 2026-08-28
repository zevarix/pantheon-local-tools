#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected outputs to match"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected help to contain [$2]" ;; esac; }

help_output=$(bash "$CLI" help)
assert_eq "$help_output" "$(bash "$CLI" --help)"
assert_eq "$help_output" "$(bash "$CLI")"

for expected in \
  'pantheon-local config init [--root PATH] [--provider auto|ddev|lando]' \
  'pantheon-local config path' \
  'pantheon-local config get KEY' \
  'pantheon-local config set KEY VALUE' \
  'pantheon-local config unset KEY' \
  'pantheon-local config list' \
  'pantheon-local config tag get TAG' \
  'pantheon-local config tag set TAG DIRECTORY' \
  'pantheon-local config tag unset TAG' \
  'pantheon-local config tag list' \
  'pantheon-local multidev SITE.ENV [--provider ddev|lando] [--group NAME] [--dry-run] [--start]' \
  'pantheon-local pull ENV [--database-only|--files-only] [--provider ddev|lando]' \
  'pantheon-local status' \
  'pantheon-local version' \
  'pantheon-local --version' \
  'auto   Detect from project configuration after checkout' \
  'pantheon-local multidev example.feature --dry-run' \
  'pantheon-local pull test --database-only'
do
  assert_contains "$help_output" "$expected"
done

config_help=$(bash "$CLI" config help)
assert_contains "$config_help" 'pantheon-local config init [--root PATH] [--provider auto|ddev|lando]'
assert_contains "$config_help" 'pantheon-local config tag set TAG DIRECTORY'

init_help=$(bash "$CLI" config init --help)
assert_contains "$init_help" 'Usage: pantheon-local config init [--root PATH] [--provider auto|ddev|lando]'
assert_contains "$init_help" 'guided setup'

multidev_help=$(bash "$CLI" multidev --help)
assert_contains "$multidev_help" 'pantheon-local multidev SITE.ENV [--provider ddev|lando] [--group NAME] [--dry-run] [--start]'

pull_help=$(bash "$CLI" pull --help)
assert_contains "$pull_help" 'pantheon-local pull ENV [--database-only|--files-only] [--provider ddev|lando]'
assert_contains "$pull_help" 'without changing checked-out Git code'

status_help=$(bash "$CLI" status --help)
assert_contains "$status_help" 'pantheon-local status'
assert_contains "$status_help" 'without contacting Pantheon or starting a provider'

printf 'help tests passed\n'
