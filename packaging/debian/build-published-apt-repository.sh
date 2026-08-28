#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools published APT repository builder'

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

[ "$#" -eq 3 ] ||
  die 'usage: build-published-apt-repository.sh OUTPUT_DIR OWNER/REPO TARGET_VERSION'

OUTPUT_DIR=$1
REPOSITORY=$2
TARGET_VERSION=${3#v}

require_command awk
require_command date
require_command dpkg
require_command dpkg-deb
require_command gh
require_command grep
require_command mktemp
require_command sha256sum

case "$REPOSITORY" in
  */*) ;;
  *) die 'repository must use OWNER/REPO form' ;;
esac

[ -n "$TARGET_VERSION" ] || die 'target version cannot be empty'
dpkg --validate-version "$TARGET_VERSION" >/dev/null 2>&1 ||
  die "invalid Debian package version: $TARGET_VERSION"

[ ! -e "$OUTPUT_DIR" ] || die "output path already exists: $OUTPUT_DIR"

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

TAGS_FILE="$TMP_ROOT/tags"
PACKAGES_FILE="$TMP_ROOT/packages"
: > "$TAGS_FILE"
: > "$PACKAGES_FILE"

gh api --paginate "repos/$REPOSITORY/releases?per_page=100" \
  --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
  > "$TAGS_FILE"

TARGET_FOUND=0

while IFS= read -r tag; do
  [ -n "$tag" ] || continue

  case "$tag" in
    v*) version=${tag#v} ;;
    *) continue ;;
  esac

  dpkg --validate-version "$version" >/dev/null 2>&1 ||
    die "stable release tag is not a valid Debian version: $tag"

  if ! dpkg --compare-versions "$version" le "$TARGET_VERSION"; then
    continue
  fi

  release_dir="$TMP_ROOT/releases/$version"
  mkdir -p "$release_dir"

  deb_name="pantheon-local-tools_${version}_all.deb"

  gh release download "$tag" \
    --repo "$REPOSITORY" \
    --pattern "$deb_name" \
    --pattern 'SHA256SUMS' \
    --dir "$release_dir" >/dev/null

  deb_file="$release_dir/$deb_name"
  sums_file="$release_dir/SHA256SUMS"

  [ -f "$deb_file" ] || die "release $tag is missing $deb_name"
  [ -f "$sums_file" ] || die "release $tag is missing SHA256SUMS"

  expected_sha=$(
    awk -v file="$deb_name" '$2 == file { print $1 }' "$sums_file"
  )

  [ -n "$expected_sha" ] ||
    die "release $tag SHA256SUMS does not contain $deb_name"
  case "$expected_sha" in
    *$'\n'*|*$'\r'*) die "release $tag has duplicate checksum entries for $deb_name" ;;
  esac
  printf '%s\n' "$expected_sha" | grep -Eq '^[0-9a-fA-F]{64}$' ||
    die "release $tag has an invalid checksum for $deb_name"

  actual_sha=$(sha256sum "$deb_file" | awk '{print $1}')
  [ "$actual_sha" = "$expected_sha" ] ||
    die "release $tag checksum mismatch for $deb_name"

  [ "$(dpkg-deb -f "$deb_file" Package)" = 'pantheon-local-tools' ] ||
    die "release $tag contains the wrong package name"
  [ "$(dpkg-deb -f "$deb_file" Version)" = "$version" ] ||
    die "release $tag package version does not match its tag"
  [ "$(dpkg-deb -f "$deb_file" Architecture)" = 'all' ] ||
    die "release $tag package architecture is not all"

  printf '%s\n' "$deb_file" >> "$PACKAGES_FILE"

  if [ "$version" = "$TARGET_VERSION" ]; then
    TARGET_FOUND=1
  fi
done < "$TAGS_FILE"

[ "$TARGET_FOUND" -eq 1 ] ||
  die "stable published release v$TARGET_VERSION was not found"

[ -s "$PACKAGES_FILE" ] || die 'no stable published Debian packages were found'

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  published_at=$(gh api "repos/$REPOSITORY/releases/tags/v$TARGET_VERSION" --jq '.published_at')
  [ -n "$published_at" ] || die "published_at is missing for v$TARGET_VERSION"
  SOURCE_DATE_EPOCH=$(date -u -d "$published_at" +%s)
  export SOURCE_DATE_EPOCH
fi

packages=()
while IFS= read -r package; do
  [ -n "$package" ] || continue
  packages+=("$package")
done < "$PACKAGES_FILE"

PANTHEON_LOCAL_APT_CURRENT_VERSION="$TARGET_VERSION" \
  bash "$REPO_ROOT/packaging/debian/build-apt-repository.sh" \
    "$OUTPUT_DIR" "${packages[@]}" >/dev/null

printf '%s\n' "$OUTPUT_DIR"
