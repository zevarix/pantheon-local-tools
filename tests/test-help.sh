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
  'pantheon-local config tag profile get TAG PROPERTY' \
  'pantheon-local config tag profile set TAG PROPERTY VALUE' \
  'pantheon-local config tag profile unset TAG PROPERTY' \
  'pantheon-local config tag profile list [TAG]' \
  'config-strategy  full-export or overlay-delta' \
  'config-path      Relative project configuration path such as config/sync' \
  'pantheon-local multidev SITE.ENV [--provider ddev|lando] [--group NAME] [--dry-run] [--start]' \
  'pantheon-local setup [--provider ddev|lando] [--dry-run]' \
  'pantheon-local readiness [--provider ddev|lando]' \
  'pantheon-local pull ENV [--database-only|--files-only] [--provider ddev|lando]' \
  'pantheon-local status' \
  'pantheon-local version' \
  'pantheon-local --version' \
  'auto   Detect from project configuration after checkout' \
  "pantheon-local config tag profile set 'Example Group' config-strategy full-export" \
  'pantheon-local multidev example.feature --dry-run' \
  'pantheon-local setup --dry-run' \
  'pantheon-local readiness' \
  'pantheon-local pull test --database-only'
do
  assert_contains "$help_output" "$expected"
done
assert_contains "$help_output" 'overlay-delta reports its protected partial path'
assert_contains "$help_output" 'fails closed while owning validation is unavailable'

config_help=$(bash "$CLI" config help)
assert_contains "$config_help" 'pantheon-local config init [--root PATH] [--provider auto|ddev|lando]'
assert_contains "$config_help" 'pantheon-local config tag set TAG DIRECTORY'
assert_contains "$config_help" 'pantheon-local config tag profile set TAG PROPERTY VALUE'

tag_help=$(bash "$CLI" config tag help)
assert_contains "$tag_help" 'pantheon-local config tag profile list [TAG]'

init_help=$(bash "$CLI" config init --help)
assert_contains "$init_help" 'Usage: pantheon-local config init [--root PATH] [--provider auto|ddev|lando]'
assert_contains "$init_help" 'guided setup'

profile_help=$(bash "$CLI" config tag profile --help)
assert_contains "$profile_help" 'pantheon-local config tag profile get TAG PROPERTY'
assert_contains "$profile_help" 'config-strategy  full-export or overlay-delta'
assert_contains "$profile_help" 'Setting a profile property never creates a tag route.'

multidev_help=$(bash "$CLI" multidev --help)
assert_contains "$multidev_help" 'pantheon-local multidev SITE.ENV [--provider ddev|lando] [--group NAME] [--dry-run] [--start]'

setup_help=$(bash "$CLI" setup --help)
assert_contains "$setup_help" 'pantheon-local setup [--provider ddev|lando] [--dry-run]'
assert_contains "$setup_help" 'provider-owned composer install'
assert_contains "$setup_help" 'replaces local database data'
assert_contains "$setup_help" 'checkout-local PLT state'
assert_contains "$setup_help" 'Setup stops on the first failed step'
assert_contains "$setup_help" 'Fix the reported failure and run pantheon-local setup again.'

readiness_help=$(bash "$CLI" readiness --help)
assert_contains "$readiness_help" 'pantheon-local readiness [--provider ddev|lando]'
assert_contains "$readiness_help" 'full-export'
assert_contains "$readiness_help" 'overlay-delta'
assert_contains "$readiness_help" 'protected partial override set'
assert_contains "$readiness_help" 'Missing YAML'
assert_contains "$readiness_help" 'No provider-owned Drush command is invoked'
assert_contains "$readiness_help" 'No drush config:export / cex is run.'
assert_contains "$readiness_help" 'still exit 0 when inspection succeeds'
assert_contains "$readiness_help" 'Owning validation remains fail-closed'
assert_contains "$readiness_help" 'Config Ignore detection is advisory for full-export.'
assert_contains "$readiness_help" 'provider is not started or rebuilt'

pull_help=$(bash "$CLI" pull --help)
assert_contains "$pull_help" 'pantheon-local pull ENV [--database-only|--files-only] [--provider ddev|lando]'
assert_contains "$pull_help" 'without changing checked-out Git code'

status_help=$(bash "$CLI" status --help)
assert_contains "$status_help" 'pantheon-local status'
assert_contains "$status_help" 'without contacting Pantheon or starting a provider'
assert_contains "$status_help" 'Drupal bootstrap status/step'

printf 'help tests passed\n'
