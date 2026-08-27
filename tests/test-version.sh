#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
EXPECTED=$(cat "$REPO_ROOT/VERSION")
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }

assert_eq "$(bash "$CLI" version)" "pantheon-local $EXPECTED"
assert_eq "$(bash "$CLI" --version)" "pantheon-local $EXPECTED"
assert_contains "$(bash "$CLI" --help)" 'pantheon-local version'
assert_contains "$(bash "$CLI" --help)" 'pantheon-local --version'

# The installed command is a symlink; version lookup must resolve back to the
# packaged project tree just like config/status/pull routing does.
mkdir -p "$TMP_ROOT/bin"
ln -s "$CLI" "$TMP_ROOT/bin/pantheon-local"
assert_eq "$("$TMP_ROOT/bin/pantheon-local" version)" "pantheon-local $EXPECTED"

if bash "$CLI" version extra >/dev/null 2>&1; then
  fail 'version unexpectedly accepted an extra argument'
fi
if bash "$CLI" --version extra >/dev/null 2>&1; then
  fail '--version unexpectedly accepted an extra argument'
fi

printf 'version tests passed\n'
