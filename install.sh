#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="pantheon-local-tools installer"

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

[ -n "${HOME:-}" ] || die 'HOME is not set'

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$SCRIPT_DIR/bin/pantheon-local"
BIN_DIR=${PANTHEON_LOCAL_BIN_DIR:-"$HOME/.local/bin"}
DESTINATION="$BIN_DIR/pantheon-local"

[ -f "$SOURCE" ] || die "command not found in repository: $SOURCE"
mkdir -p "$BIN_DIR"

if [ -L "$DESTINATION" ]; then
  CURRENT_TARGET=$(readlink "$DESTINATION" || true)
  [ "$CURRENT_TARGET" = "$SOURCE" ] || die "refusing to replace existing symlink: $DESTINATION"
elif [ -e "$DESTINATION" ]; then
  die "refusing to replace existing path: $DESTINATION"
else
  ln -s "$SOURCE" "$DESTINATION"
fi

printf 'Installed pantheon-local -> %s\n' "$SOURCE"
printf 'Command path: %s\n' "$DESTINATION"

case ":${PATH:-}:" in
  *":$BIN_DIR:"*) ;;
  *) printf 'Add %s to PATH to run pantheon-local from any directory.\n' "$BIN_DIR" ;;
esac
