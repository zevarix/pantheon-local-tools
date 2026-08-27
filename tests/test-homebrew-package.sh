#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
FORMULA_NAME='pantheon-local-tools'
TAP='zevarix-ci/pantheon-local-tools-ci'
FULL_FORMULA="$TAP/$FORMULA_NAME"

cleanup() {
  if command -v brew >/dev/null 2>&1; then
    if brew list --formula "$FORMULA_NAME" >/dev/null 2>&1; then
      HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 \
        brew uninstall --force "$FORMULA_NAME" >/dev/null 2>&1 || true
    fi
    if brew tap | grep -Fx "$TAP" >/dev/null 2>&1; then
      HOMEBREW_NO_AUTO_UPDATE=1 brew untap "$TAP" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }

if ! command -v brew >/dev/null 2>&1; then
  printf 'homebrew package tests skipped (brew unavailable)\n'
  exit 0
fi

if brew list --formula "$FORMULA_NAME" >/dev/null 2>&1; then
  fail "$FORMULA_NAME is already installed in the test environment"
fi
if brew tap | grep -Fx "$TAP" >/dev/null 2>&1; then
  fail "$TAP is already present in the test environment"
fi

VERSION=$(cat "$REPO_ROOT/VERSION")
ARCHIVE="$TMP_ROOT/pantheon-local-tools-$VERSION.tar.gz"

git -C "$REPO_ROOT" archive --format=tar HEAD | gzip -n > "$ARCHIVE"
SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
URL="file://$ARCHIVE"

HOMEBREW_NO_AUTO_UPDATE=1 brew tap-new --no-git "$TAP" >/dev/null
TAP_ROOT=$(brew --repository "$TAP")
FORMULA="$TAP_ROOT/Formula/pantheon-local-tools.rb"

bash "$REPO_ROOT/packaging/homebrew/render-formula.sh" "$VERSION" "$URL" "$SHA256" "$FORMULA" >/dev/null
ruby -c "$FORMULA" >/dev/null

HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 \
  brew install --build-from-source "$FULL_FORMULA" >/dev/null
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 \
  brew test "$FULL_FORMULA" >/dev/null

PREFIX=$(brew --prefix "$FORMULA_NAME")
[ -x "$PREFIX/libexec/bin/pantheon-local" ] || fail 'Homebrew command payload is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-core" ] || fail 'Homebrew core module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-provider-url" ] || fail 'Homebrew provider URL module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-pull" ] || fail 'Homebrew pull module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-status" ] || fail 'Homebrew status module is missing'
[ -f "$PREFIX/libexec/VERSION" ] || fail 'Homebrew VERSION is missing'

expected="pantheon-local $VERSION"
assert_eq "$(pantheon-local --version)" "$expected"
assert_eq "$(pantheon-local version)" "$expected"

TEST_HOME="$TMP_ROOT/home"
mkdir -p "$TEST_HOME"
assert_eq "$(HOME="$TEST_HOME" pantheon-local config path)" "$TEST_HOME/.config/pantheon-local-tools/config"

printf 'homebrew package tests passed\n'
