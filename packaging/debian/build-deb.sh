#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools Debian builder'

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
OUTPUT_DIR=${1:-"$REPO_ROOT/dist"}
VERSION_FILE="$REPO_ROOT/VERSION"

require_command dpkg-deb
require_command install

[ -f "$VERSION_FILE" ] || die "VERSION file not found: $VERSION_FILE"
VERSION=$(cat "$VERSION_FILE")
[ -n "$VERSION" ] || die 'VERSION cannot be empty'
case "$VERSION" in
  *$'\n'*|*$'\r'*) die 'VERSION must be a single line' ;;
esac

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
PACKAGE_FILE="$OUTPUT_DIR/pantheon-local-tools_${VERSION}_all.deb"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM

APP_ROOT="$STAGE/usr/lib/pantheon-local-tools"
DOC_ROOT="$STAGE/usr/share/doc/pantheon-local-tools"
CONTROL_ROOT="$STAGE/DEBIAN"

install -d "$APP_ROOT/bin" "$APP_ROOT/libexec" "$STAGE/usr/bin" "$DOC_ROOT" "$CONTROL_ROOT"
install -m 0755 "$REPO_ROOT/bin/pantheon-local" "$APP_ROOT/bin/pantheon-local"
install -m 0755 "$REPO_ROOT/libexec/pantheon-local-core" "$APP_ROOT/libexec/pantheon-local-core"
install -m 0755 "$REPO_ROOT/libexec/pantheon-local-config-profile" "$APP_ROOT/libexec/pantheon-local-config-profile"
install -m 0755 "$REPO_ROOT/libexec/pantheon-local-provider-url" "$APP_ROOT/libexec/pantheon-local-provider-url"
install -m 0755 "$REPO_ROOT/libexec/pantheon-local-pull" "$APP_ROOT/libexec/pantheon-local-pull"
install -m 0755 "$REPO_ROOT/libexec/pantheon-local-status" "$APP_ROOT/libexec/pantheon-local-status"
install -m 0644 "$VERSION_FILE" "$APP_ROOT/VERSION"
install -m 0644 "$REPO_ROOT/LICENSE" "$DOC_ROOT/copyright"
install -m 0644 "$REPO_ROOT/README.md" "$DOC_ROOT/README.md"

ln -s '../lib/pantheon-local-tools/bin/pantheon-local' "$STAGE/usr/bin/pantheon-local"

cat > "$CONTROL_ROOT/control" <<EOF
Package: pantheon-local-tools
Version: $VERSION
Section: devel
Priority: optional
Architecture: all
Maintainer: zevarix <zevarix@users.noreply.github.com>
Depends: bash, git
Homepage: https://github.com/zevarix/pantheon-local-tools
Description: Provider-neutral local development helpers for Pantheon
 Pantheon Local Tools provides a consistent CLI for Pantheon multidev
 checkout, data pull, and local status workflows with DDEV and Lando.
EOF

chmod 0755 "$CONTROL_ROOT"
chmod 0644 "$CONTROL_ROOT/control"

dpkg-deb --root-owner-group --build "$STAGE" "$PACKAGE_FILE" >/dev/null
printf '%s\n' "$PACKAGE_FILE"
