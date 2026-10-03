#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools release builder'

fail() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

sha256_file() {
  local file=$1
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    fail 'required SHA256 tool not found: install shasum or sha256sum'
  fi
}

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
VERSION_FILE="$REPO_ROOT/VERSION"
[ -f "$VERSION_FILE" ] || fail "VERSION not found: $VERSION_FILE"
VERSION=$(cat "$VERSION_FILE")
[ -n "$VERSION" ] || fail 'VERSION cannot be empty'
printf '%s\n' "$VERSION" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' || \
  fail "VERSION is not a supported SemVer-like value: $VERSION"

require_command git

CANONICAL_COMPRESSOR="$REPO_ROOT/packaging/release/compress-source-canonical.sh"
[ -r "$CANONICAL_COMPRESSOR" ] || fail "canonical source compressor is missing: $CANONICAL_COMPRESSOR"

OUT_DIR=${1:-"$REPO_ROOT/dist"}
case "$OUT_DIR" in
  /*) ;;
  *) OUT_DIR="$REPO_ROOT/$OUT_DIR" ;;
esac
mkdir -p "$OUT_DIR"
OUT_DIR=$(cd -- "$OUT_DIR" && pwd -P)

HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)
TAG="v$VERSION"
ARCHIVE_REF=$TAG

ALLOW_UNTAGGED=${PANTHEON_LOCAL_RELEASE_ALLOW_UNTAGGED:-0}
if [ "$ALLOW_UNTAGGED" = '1' ]; then
  ARCHIVE_REF=$HEAD_SHA
  COMPRESSION_MODE=${PANTHEON_LOCAL_RELEASE_COMPRESSION:-host}
  case "$COMPRESSION_MODE" in
    host|canonical) ;;
    *) fail 'PANTHEON_LOCAL_RELEASE_COMPRESSION must be host or canonical' ;;
  esac
else
  TAG_SHA=$(git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG^{commit}" 2>/dev/null || true)
  [ -n "$TAG_SHA" ] || fail "release tag does not exist: $TAG"
  [ "$TAG_SHA" = "$HEAD_SHA" ] || fail "release tag $TAG does not point at current HEAD $HEAD_SHA"
  COMPRESSION_MODE=canonical
  if [ -n "${PANTHEON_LOCAL_RELEASE_COMPRESSION:-}" ] && [ "${PANTHEON_LOCAL_RELEASE_COMPRESSION}" != canonical ]; then
    fail 'tagged release builds require canonical compression'
  fi
fi

SOURCE_NAME="pantheon-local-tools-$VERSION.tar.gz"
SOURCE_PATH="$OUT_DIR/$SOURCE_NAME"
TMP_TAR="$OUT_DIR/.pantheon-local-tools-$VERSION.tar.tmp.$$"
TMP_SOURCE="$OUT_DIR/.$SOURCE_NAME.tmp.$$"
trap 'rm -f "$TMP_TAR" "$TMP_SOURCE"' EXIT HUP INT TERM

git -C "$REPO_ROOT" archive \
  --format=tar \
  --prefix="pantheon-local-tools-$VERSION/" \
  "$ARCHIVE_REF" > "$TMP_TAR"

case "$COMPRESSION_MODE" in
  canonical)
    bash "$CANONICAL_COMPRESSOR" < "$TMP_TAR" > "$TMP_SOURCE"
    ;;
  host)
    require_command gzip
    gzip -n < "$TMP_TAR" > "$TMP_SOURCE"
    ;;
esac

rm -f "$TMP_TAR"
mv "$TMP_SOURCE" "$SOURCE_PATH"
trap - EXIT HUP INT TERM

DEB_PATH=''
if command -v dpkg-deb >/dev/null 2>&1; then
  DEB_PATH=$(bash "$REPO_ROOT/packaging/debian/build-deb.sh" "$OUT_DIR")
fi

CHECKSUM_PATH="$OUT_DIR/SHA256SUMS"
: > "$CHECKSUM_PATH"
SOURCE_SHA=$(sha256_file "$SOURCE_PATH")
printf '%s  %s\n' "$SOURCE_SHA" "$SOURCE_NAME" >> "$CHECKSUM_PATH"

if [ -n "$DEB_PATH" ]; then
  DEB_NAME=${DEB_PATH##*/}
  DEB_SHA=$(sha256_file "$DEB_PATH")
  printf '%s  %s\n' "$DEB_SHA" "$DEB_NAME" >> "$CHECKSUM_PATH"
fi

printf 'Release artifact set\n\n'
printf 'Version:       %s\n' "$VERSION"
printf 'Git ref:       %s\n' "$ARCHIVE_REF"
printf 'Git SHA:       %s\n' "$HEAD_SHA"
printf 'Compression:   %s\n' "$COMPRESSION_MODE"
printf 'Source:        %s\n' "$SOURCE_PATH"
printf 'Source SHA256: %s\n' "$SOURCE_SHA"
if [ -n "$DEB_PATH" ]; then
  printf 'Debian:        %s\n' "$DEB_PATH"
else
  printf 'Debian:        (not built; dpkg-deb unavailable)\n'
fi
printf 'Checksums:     %s\n' "$CHECKSUM_PATH"
