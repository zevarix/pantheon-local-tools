#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    fail 'SHA256 tool unavailable'
  fi
}

VERSION=$(cat "$REPO_ROOT/VERSION")
OUT_ONE="$TMP_ROOT/one"
OUT_TWO="$TMP_ROOT/two"

PANTHEON_LOCAL_RELEASE_ALLOW_UNTAGGED=1 \
  bash "$REPO_ROOT/packaging/release/build-artifacts.sh" "$OUT_ONE" >/dev/null
PANTHEON_LOCAL_RELEASE_ALLOW_UNTAGGED=1 \
  bash "$REPO_ROOT/packaging/release/build-artifacts.sh" "$OUT_TWO" >/dev/null

SOURCE_NAME="pantheon-local-tools-$VERSION.tar.gz"
SOURCE_ONE="$OUT_ONE/$SOURCE_NAME"
SOURCE_TWO="$OUT_TWO/$SOURCE_NAME"
[ -f "$SOURCE_ONE" ] || fail 'release source archive was not created'
[ -f "$SOURCE_TWO" ] || fail 'second release source archive was not created'
[ -f "$OUT_ONE/SHA256SUMS" ] || fail 'SHA256SUMS was not created'

SHA_ONE=$(sha256_file "$SOURCE_ONE")
SHA_TWO=$(sha256_file "$SOURCE_TWO")
assert_eq "$SHA_ONE" "$SHA_TWO"
grep -F "$SHA_ONE  $SOURCE_NAME" "$OUT_ONE/SHA256SUMS" >/dev/null 2>&1 || \
  fail 'source archive checksum is missing from SHA256SUMS'

PREFIX="pantheon-local-tools-$VERSION"
tar -tzf "$SOURCE_ONE" | grep -Fx "$PREFIX/VERSION" >/dev/null 2>&1 || fail 'VERSION missing from source archive'
tar -tzf "$SOURCE_ONE" | grep -Fx "$PREFIX/bin/pantheon-local" >/dev/null 2>&1 || fail 'CLI missing from source archive'
tar -tzf "$SOURCE_ONE" | grep -Fx "$PREFIX/libexec/pantheon-local-core" >/dev/null 2>&1 || fail 'core module missing from source archive'
if tar -tzf "$SOURCE_ONE" | grep -E '/\.git(/|$)|/dist(/|$)|/\.agents(/|$)' >/dev/null 2>&1; then
  fail 'source archive contains repository-local/private build state'
fi

EXTRACT="$TMP_ROOT/extract"
mkdir -p "$EXTRACT"
tar -xzf "$SOURCE_ONE" -C "$EXTRACT"
expected="pantheon-local $VERSION"
assert_eq "$(bash "$EXTRACT/$PREFIX/bin/pantheon-local" --version)" "$expected"

if command -v dpkg-deb >/dev/null 2>&1; then
  DEB_NAME="pantheon-local-tools_${VERSION}_all.deb"
  DEB_PATH="$OUT_ONE/$DEB_NAME"
  [ -f "$DEB_PATH" ] || fail 'Debian release artifact was not created when dpkg-deb is available'
  DEB_SHA=$(sha256_file "$DEB_PATH")
  grep -F "$DEB_SHA  $DEB_NAME" "$OUT_ONE/SHA256SUMS" >/dev/null 2>&1 || \
    fail 'Debian artifact checksum is missing from SHA256SUMS'
fi

printf 'release artifact tests passed\n'
