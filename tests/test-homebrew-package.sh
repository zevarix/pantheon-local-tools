#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
FORMULA_NAME='pantheon-local-tools'
TAP='zevarix-ci/pantheon-local-tools-ci'
FULL_FORMULA="$TAP/$FORMULA_NAME"
CORE_TAP='homebrew/core'
BREW_DEVELOPER_WAS_ENABLED=0
BREW_CORE_WAS_TAPPED=0

cleanup() {
  if command -v brew >/dev/null 2>&1; then
    if brew list --formula "$FORMULA_NAME" >/dev/null 2>&1; then
      HOMEBREW_NO_AUTO_UPDATE=1 \
        brew uninstall --force "$FORMULA_NAME" >/dev/null 2>&1 || true
    fi
    if brew tap | grep -Fx "$TAP" >/dev/null 2>&1; then
      HOMEBREW_NO_AUTO_UPDATE=1 brew untap "$TAP" >/dev/null 2>&1 || true
    fi
    if [ "$BREW_CORE_WAS_TAPPED" -eq 0 ] && brew tap | grep -Fx "$CORE_TAP" >/dev/null 2>&1; then
      HOMEBREW_NO_AUTO_UPDATE=1 brew untap "$CORE_TAP" >/dev/null 2>&1 || true
    fi
    if [ "$BREW_DEVELOPER_WAS_ENABLED" -eq 0 ]; then
      HOMEBREW_NO_AUTO_UPDATE=1 brew developer off >/dev/null 2>&1 || true
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

if brew developer 2>/dev/null | grep -qi 'enabled'; then
  BREW_DEVELOPER_WAS_ENABLED=1
fi
if brew tap | grep -Fx "$CORE_TAP" >/dev/null 2>&1; then
  BREW_CORE_WAS_TAPPED=1
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

if grep -Eq '^[[:space:]]*version[[:space:]]' "$FORMULA"; then
  fail 'Homebrew formula should infer its version from the release URL'
fi

if grep -Fq 'uses_from_macos "git"' "$FORMULA"; then
  fail 'Homebrew formula should not declare git as a dependency'
fi

HOMEBREW_NO_AUTO_UPDATE=1 \
  brew style "$FULL_FORMULA" >/dev/null

HOMEBREW_NO_AUTO_UPDATE=1 \
  brew install --build-from-source "$FULL_FORMULA" >/dev/null
HOMEBREW_NO_AUTO_UPDATE=1 \
  brew test "$FULL_FORMULA" >/dev/null

PREFIX=$(brew --prefix "$FORMULA_NAME")
FORMULA_CLI="$PREFIX/bin/pantheon-local"
[ -x "$FORMULA_CLI" ] || fail 'Homebrew public command is missing'
[ -x "$PREFIX/libexec/bin/pantheon-local" ] || fail 'Homebrew command payload is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-core" ] || fail 'Homebrew core module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-config-profile" ] || fail 'Homebrew tag-profile module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-config-export" ] || fail 'Homebrew config-export module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-multidev-create" ] || fail 'Homebrew multidev-create module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-provider-url" ] || fail 'Homebrew provider URL module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-pull" ] || fail 'Homebrew pull module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-readiness" ] || fail 'Homebrew readiness module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-setup" ] || fail 'Homebrew setup module is missing'
[ -x "$PREFIX/libexec/libexec/pantheon-local-status" ] || fail 'Homebrew status module is missing'
[ -f "$PREFIX/libexec/VERSION" ] || fail 'Homebrew VERSION is missing'

expected="pantheon-local $VERSION"
assert_eq "$("$FORMULA_CLI" --version)" "$expected"
assert_eq "$("$FORMULA_CLI" version)" "$expected"
"$FORMULA_CLI" config export --help | grep -F 'MUTATES PROJECT CONFIGURATION FILES' >/dev/null 2>&1 || fail 'Homebrew config export help is unavailable'
"$FORMULA_CLI" multidev create --help | grep -F 'EXPLICIT REMOTE PANTHEON WRITE' >/dev/null 2>&1 || fail 'Homebrew multidev create help is unavailable'
"$FORMULA_CLI" setup --help | grep -F 'pantheon-local setup' >/dev/null 2>&1 || fail 'Homebrew setup help is unavailable'
"$FORMULA_CLI" readiness --help | grep -F 'pantheon-local readiness' >/dev/null 2>&1 || fail 'Homebrew readiness help is unavailable'

TEST_HOME="$TMP_ROOT/home"
CALLER_CONFIG="$TMP_ROOT/caller-config"
mkdir -p "$TEST_HOME"
assert_eq "$(PANTHEON_LOCAL_CONFIG="$CALLER_CONFIG" "$FORMULA_CLI" config path)" "$CALLER_CONFIG"
DEFAULT_CONFIG_PATH=$(
  unset PANTHEON_LOCAL_CONFIG XDG_CONFIG_HOME
  HOME="$TEST_HOME" "$FORMULA_CLI" config path
)
assert_eq "$DEFAULT_CONFIG_PATH" "$TEST_HOME/.config/pantheon-local-tools/config"

printf 'homebrew package tests passed\n'
