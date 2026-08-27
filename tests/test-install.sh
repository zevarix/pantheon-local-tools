#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }

export HOME="$TMP_ROOT/home"
unset XDG_CONFIG_HOME PANTHEON_LOCAL_CONFIG
mkdir -p "$HOME"

BIN_DIR="$TMP_ROOT/bin"
install_output=$(PANTHEON_LOCAL_BIN_DIR="$BIN_DIR" bash "$REPO_ROOT/install.sh")

[ -L "$BIN_DIR/pantheon-local" ] || fail 'installer did not create the command symlink'
assert_eq "$(readlink "$BIN_DIR/pantheon-local")" "$REPO_ROOT/bin/pantheon-local"
assert_contains "$install_output" "Installed pantheon-local -> $REPO_ROOT/bin/pantheon-local"
assert_contains "$install_output" "Command path: $BIN_DIR/pantheon-local"

expected_version="pantheon-local $(cat "$REPO_ROOT/VERSION")"
assert_eq "$("$BIN_DIR/pantheon-local" --version)" "$expected_version"
assert_eq "$("$BIN_DIR/pantheon-local" version)" "$expected_version"

expected_config="$HOME/.config/pantheon-local-tools/config"
assert_eq "$("$BIN_DIR/pantheon-local" config path)" "$expected_config"
"$BIN_DIR/pantheon-local" config set provider lando
assert_eq "$("$BIN_DIR/pantheon-local" config get provider)" 'lando'
[ -f "$expected_config" ] || fail 'installed command did not create configuration in the isolated HOME'

# Reinstalling the same checkout is idempotent.
PANTHEON_LOCAL_BIN_DIR="$BIN_DIR" bash "$REPO_ROOT/install.sh" >/dev/null
assert_eq "$(readlink "$BIN_DIR/pantheon-local")" "$REPO_ROOT/bin/pantheon-local"

# The installer must not mutate shell startup files.
for rc in .bashrc .bash_profile .profile .zshrc .zprofile; do
  [ ! -e "$HOME/$rc" ] || fail "installer unexpectedly created or changed $HOME/$rc"
done

# An unrelated existing regular file is never overwritten.
FILE_COLLISION="$TMP_ROOT/file-collision-bin"
mkdir -p "$FILE_COLLISION"
printf 'unrelated command\n' > "$FILE_COLLISION/pantheon-local"
if PANTHEON_LOCAL_BIN_DIR="$FILE_COLLISION" bash "$REPO_ROOT/install.sh" >/dev/null 2>&1; then
  fail 'installer overwrote an unrelated existing file'
fi
assert_eq "$(cat "$FILE_COLLISION/pantheon-local")" 'unrelated command'

# An unrelated symlink is never replaced either.
SYMLINK_COLLISION="$TMP_ROOT/symlink-collision-bin"
mkdir -p "$SYMLINK_COLLISION"
ln -s "$TMP_ROOT/not-this-repository" "$SYMLINK_COLLISION/pantheon-local"
if PANTHEON_LOCAL_BIN_DIR="$SYMLINK_COLLISION" bash "$REPO_ROOT/install.sh" >/dev/null 2>&1; then
  fail 'installer replaced an unrelated symlink'
fi
assert_eq "$(readlink "$SYMLINK_COLLISION/pantheon-local")" "$TMP_ROOT/not-this-repository"

printf 'install tests passed\n'
