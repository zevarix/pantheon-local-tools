#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME="pantheon-local-tools installer"

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

[ -n "${HOME:-}" ] || die 'HOME is not set'

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$SCRIPT_DIR/bin/pantheon-local"
BIN_DIR=${PANTHEON_LOCAL_BIN_DIR:-"$HOME/.local/bin"}

[ -f "$SOURCE" ] || die "command not found in repository: $SOURCE"
mkdir -p "$BIN_DIR"

# Check both names before creating either, so a collision cannot leave
# a partial installation. Existing matching symlinks are idempotent.
for command_name in pantheon-local plt; do
  destination="$BIN_DIR/$command_name"
  if [ -L "$destination" ]; then
    current_target=$(readlink "$destination" || true)
    [ "$current_target" = "$SOURCE" ] || die "refusing to replace existing symlink: $destination"
  elif [ -e "$destination" ]; then
    die "refusing to replace existing path: $destination"
  fi
done

for command_name in pantheon-local plt; do
  destination="$BIN_DIR/$command_name"
  [ -L "$destination" ] || ln -s "$SOURCE" "$destination"
  printf 'Installed %s -> %s\n' "$command_name" "$SOURCE"
  printf 'Command path: %s\n' "$destination"
done

case ":${PATH:-}:" in
  *":$BIN_DIR:"*) ;;
  *) printf 'Add %s to PATH to run pantheon-local or plt from any directory.\n' "$BIN_DIR" ;;
esac
