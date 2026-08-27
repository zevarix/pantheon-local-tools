#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }

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
      printf 'name: example-site\ntype: drupal11\n' > "$path/.ddev/config.yaml"
      ;;
    *) fail "unknown provider fixture: $provider" ;;
  esac

  printf 'fixture\n' > "$path/README.md"
  git -C "$path" add .
  git -C "$path" commit -qm 'Create status fixture'
}

assert_contains "$(bash "$CLI" --help)" 'pantheon-local status'

MANAGED="$TMP_ROOT/managed"
create_repo "$MANAGED" lando
mkdir -p "$MANAGED/subdir" "$MANAGED/.git/pantheon-local-tools"
STATE="$MANAGED/.git/pantheon-local-tools/state"
git config --file "$STATE" pantheon.site example-site
git config --file "$STATE" pantheon.environment feature1
git config --file "$STATE" pantheon.tag 'Example Group'
git config --file "$STATE" local.provider lando
git config --file "$STATE" local.name example-site-feature1
git config --file "$STATE" local.url http://example-site-feature1.lndo.site

managed_output=$(cd "$MANAGED/subdir" && bash "$CLI" status)
assert_contains "$managed_output" "Directory:       $MANAGED"
assert_contains "$managed_output" 'Managed:         yes'
assert_contains "$managed_output" 'Pantheon:        example-site.feature1'
assert_contains "$managed_output" 'Tag:             Example Group'
assert_contains "$managed_output" 'Provider:        lando'
assert_contains "$managed_output" 'Provider config: present'
assert_contains "$managed_output" 'Local name:      example-site-feature1'
assert_contains "$managed_output" 'Local URL:       http://example-site-feature1.lndo.site'
assert_contains "$managed_output" 'Git state:       clean'
assert_contains "$managed_output" 'Data source:     (not recorded)'

printf 'dirty\n' >> "$MANAGED/README.md"
dirty_output=$(cd "$MANAGED" && bash "$CLI" status)
assert_contains "$dirty_output" 'Git state:       modified'
git -C "$MANAGED" checkout -q -- README.md

UNMANAGED="$TMP_ROOT/unmanaged"
create_repo "$UNMANAGED" ddev
unmanaged_output=$(cd "$UNMANAGED" && bash "$CLI" status)
assert_contains "$unmanaged_output" 'Managed:         no'
assert_contains "$unmanaged_output" 'Pantheon:        (not recorded)'
assert_contains "$unmanaged_output" 'Provider:        ddev (detected)'
assert_contains "$unmanaged_output" 'Provider config: present'
assert_contains "$unmanaged_output" 'Local name:      (not recorded)'

# The installed command is a symlink, so the router must resolve its real script directory.
mkdir -p "$TMP_ROOT/bin"
ln -s "$CLI" "$TMP_ROOT/bin/pantheon-local"
symlink_output=$(cd "$MANAGED" && "$TMP_ROOT/bin/pantheon-local" status)
assert_contains "$symlink_output" 'Pantheon:        example-site.feature1'

if (cd "$TMP_ROOT" && bash "$CLI" status >/dev/null 2>&1); then
  fail 'status unexpectedly succeeded outside a Git checkout'
fi

if (cd "$MANAGED" && bash "$CLI" status extra >/dev/null 2>&1); then
  fail 'status unexpectedly accepted an extra argument'
fi

printf 'status tests passed\n'
