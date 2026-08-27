#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }

if ! command -v dpkg-deb >/dev/null 2>&1; then
  printf 'debian package tests skipped (dpkg-deb unavailable)\n'
  exit 0
fi

PACKAGE=$(bash "$REPO_ROOT/packaging/debian/build-deb.sh" "$TMP_ROOT/dist")
[ -f "$PACKAGE" ] || fail 'Debian builder did not create a package'

VERSION=$(cat "$REPO_ROOT/VERSION")
assert_eq "$(dpkg-deb -f "$PACKAGE" Package)" 'pantheon-local-tools'
assert_eq "$(dpkg-deb -f "$PACKAGE" Version)" "$VERSION"
assert_eq "$(dpkg-deb -f "$PACKAGE" Architecture)" 'all'
assert_eq "$(dpkg-deb -f "$PACKAGE" Depends)" 'bash, git'

EXTRACT="$TMP_ROOT/root"
mkdir -p "$EXTRACT"
dpkg-deb -x "$PACKAGE" "$EXTRACT"

[ -x "$EXTRACT/usr/lib/pantheon-local-tools/bin/pantheon-local" ] || fail 'packaged command is missing or not executable'
[ -x "$EXTRACT/usr/lib/pantheon-local-tools/libexec/pantheon-local-core" ] || fail 'packaged core module is missing or not executable'
[ -x "$EXTRACT/usr/lib/pantheon-local-tools/libexec/pantheon-local-provider-url" ] || fail 'packaged URL module is missing or not executable'
[ -x "$EXTRACT/usr/lib/pantheon-local-tools/libexec/pantheon-local-pull" ] || fail 'packaged pull module is missing or not executable'
[ -x "$EXTRACT/usr/lib/pantheon-local-tools/libexec/pantheon-local-status" ] || fail 'packaged status module is missing or not executable'
[ -f "$EXTRACT/usr/lib/pantheon-local-tools/VERSION" ] || fail 'packaged VERSION is missing'
[ -L "$EXTRACT/usr/bin/pantheon-local" ] || fail 'packaged command link is missing'
assert_eq "$(readlink "$EXTRACT/usr/bin/pantheon-local")" '../lib/pantheon-local-tools/bin/pantheon-local'

expected="pantheon-local $VERSION"
assert_eq "$("$EXTRACT/usr/bin/pantheon-local" --version)" "$expected"
assert_eq "$("$EXTRACT/usr/bin/pantheon-local" version)" "$expected"

export HOME="$TMP_ROOT/home"
unset XDG_CONFIG_HOME PANTHEON_LOCAL_CONFIG
mkdir -p "$HOME"
assert_eq "$("$EXTRACT/usr/bin/pantheon-local" config path)" "$HOME/.config/pantheon-local-tools/config"
"$EXTRACT/usr/bin/pantheon-local" config set provider ddev
assert_eq "$("$EXTRACT/usr/bin/pantheon-local" config get provider)" 'ddev'

# Packaging must not ship user state, provider project configuration, or credentials.
if find "$EXTRACT" -type f -o -type l | grep -E '/\.config/|/\.lando|/\.ddev|pantheon-local-tools/state|machine-token' >/dev/null 2>&1; then
  fail 'Debian package unexpectedly contains user/provider state'
fi

printf 'debian package tests passed\n'
