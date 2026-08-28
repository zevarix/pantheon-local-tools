#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools APT repository builder'

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

[ "$#" -ge 2 ] || die 'usage: build-apt-repository.sh OUTPUT_DIR PACKAGE [PACKAGE ...]'

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
VERSION_FILE="$REPO_ROOT/VERSION"
OUTPUT_DIR=$1
shift

require_command awk
require_command basename
require_command date
require_command dirname
require_command dpkg-deb
require_command dpkg-scanpackages
require_command grep
require_command gzip
require_command install
require_command mktemp
require_command mv
require_command sha256sum
require_command sha512sum
require_command tr
require_command wc

[ -f "$VERSION_FILE" ] || die "VERSION file not found: $VERSION_FILE"
CURRENT_VERSION=${PANTHEON_LOCAL_APT_CURRENT_VERSION:-$(cat "$VERSION_FILE")}
[ -n "$CURRENT_VERSION" ] || die 'current repository version cannot be empty'
case "$CURRENT_VERSION" in
  *$'\n'*|*$'\r'*) die 'current repository version must be a single line' ;;
esac

case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$PWD/$OUTPUT_DIR" ;;
esac

[ ! -e "$OUTPUT_DIR" ] || die "output path already exists: $OUTPUT_DIR"
OUTPUT_PARENT=$(dirname "$OUTPUT_DIR")
mkdir -p "$OUTPUT_PARENT"
OUTPUT_PARENT=$(cd "$OUTPUT_PARENT" && pwd)
OUTPUT_DIR="$OUTPUT_PARENT/$(basename "$OUTPUT_DIR")"

STAGE=$(mktemp -d "$OUTPUT_PARENT/.pantheon-local-tools-apt.XXXXXX")
chmod 0755 "$STAGE"
VERSIONS_FILE="$STAGE/.versions"
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
: > "$VERSIONS_FILE"

POOL_REL='pool/main/p/pantheon-local-tools'
INDEX_REL='dists/stable/main/binary-all'
install -d "$STAGE/$POOL_REL" "$STAGE/$INDEX_REL"

CURRENT_VERSION_PRESENT=0

for package in "$@"; do
  [ -f "$package" ] || die "package not found: $package"

  package_name=$(dpkg-deb -f "$package" Package)
  package_version=$(dpkg-deb -f "$package" Version)
  package_architecture=$(dpkg-deb -f "$package" Architecture)

  [ "$package_name" = 'pantheon-local-tools' ] ||
    die "unexpected package name in $package: $package_name"
  [ "$package_architecture" = 'all' ] ||
    die "unexpected package architecture in $package: $package_architecture"
  [ -n "$package_version" ] || die "package version is empty: $package"

  case "$package_version" in
    *$'\n'*|*$'\r'*) die "package version must be a single line: $package" ;;
  esac

  if grep -Fx "$package_version" "$VERSIONS_FILE" >/dev/null 2>&1; then
    die "duplicate package version: $package_version"
  fi
  printf '%s\n' "$package_version" >> "$VERSIONS_FILE"

  if [ "$package_version" = "$CURRENT_VERSION" ]; then
    CURRENT_VERSION_PRESENT=1
  fi

  destination="$STAGE/$POOL_REL/pantheon-local-tools_${package_version}_all.deb"
  install -m 0644 "$package" "$destination"
done

[ "$CURRENT_VERSION_PRESENT" -eq 1 ] ||
  die "no input package matches repository VERSION $CURRENT_VERSION"

rm -f "$VERSIONS_FILE"

PACKAGES="$STAGE/$INDEX_REL/Packages"
PACKAGES_GZ="$PACKAGES.gz"

(
  cd "$STAGE"
  dpkg-scanpackages --arch all --multiversion "$POOL_REL"
) > "$PACKAGES"

gzip -n -9 -c "$PACKAGES" > "$PACKAGES_GZ"

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  printf '%s\n' "$SOURCE_DATE_EPOCH" | grep -Eq '^[0-9]+$' ||
    die 'SOURCE_DATE_EPOCH must be an integer'
  RELEASE_DATE=$(date -u -R -d "@$SOURCE_DATE_EPOCH")
else
  RELEASE_DATE=$(date -u -R)
fi

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

sha512_file() {
  sha512sum "$1" | awk '{print $1}'
}

RELEASE="$STAGE/dists/stable/Release"

cat > "$RELEASE" <<EOF_RELEASE
Origin: Pantheon Local Tools
Label: Pantheon Local Tools
Suite: stable
Codename: stable
Date: $RELEASE_DATE
Architectures: all
Components: main
Description: Pantheon Local Tools APT repository
SHA256:
 $(sha256_file "$PACKAGES") $(file_size "$PACKAGES") main/binary-all/Packages
 $(sha256_file "$PACKAGES_GZ") $(file_size "$PACKAGES_GZ") main/binary-all/Packages.gz
SHA512:
 $(sha512_file "$PACKAGES") $(file_size "$PACKAGES") main/binary-all/Packages
 $(sha512_file "$PACKAGES_GZ") $(file_size "$PACKAGES_GZ") main/binary-all/Packages.gz
EOF_RELEASE

mv "$STAGE" "$OUTPUT_DIR"
trap - EXIT HUP INT TERM

printf '%s\n' "$OUTPUT_DIR"
