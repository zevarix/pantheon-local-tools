#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
chmod 0755 "$TMP_ROOT"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "expected [$2], got [$1]"
}

for command_name in \
  apt-cache apt-get dpkg-deb dpkg-scanpackages gpg gpgv sha256sum sha512sum
do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'apt repository tests skipped (%s unavailable)\n' "$command_name"
    exit 0
  fi
done

VERSION=$(cat "$REPO_ROOT/VERSION")
PACKAGE=$(bash "$REPO_ROOT/packaging/debian/build-deb.sh" "$TMP_ROOT/package")

REPOSITORY_ONE="$TMP_ROOT/repository-one"
REPOSITORY_TWO="$TMP_ROOT/repository-two"
SOURCE_DATE_EPOCH=1787875200
export SOURCE_DATE_EPOCH

bash "$REPO_ROOT/packaging/debian/build-apt-repository.sh" \
  "$REPOSITORY_ONE" "$PACKAGE" >/dev/null

bash "$REPO_ROOT/packaging/debian/build-apt-repository.sh" \
  "$REPOSITORY_TWO" "$PACKAGE" >/dev/null

diff -ru "$REPOSITORY_ONE" "$REPOSITORY_TWO" >/dev/null ||
  fail 'APT repository metadata is not reproducible with fixed SOURCE_DATE_EPOCH'

PACKAGES="$REPOSITORY_ONE/dists/stable/main/binary-all/Packages"
PACKAGES_GZ="$PACKAGES.gz"
RELEASE="$REPOSITORY_ONE/dists/stable/Release"
POOL_PACKAGE="$REPOSITORY_ONE/pool/main/p/pantheon-local-tools/pantheon-local-tools_${VERSION}_all.deb"

[ -f "$POOL_PACKAGE" ] || fail 'APT pool package is missing'
[ -f "$PACKAGES" ] || fail 'APT Packages index is missing'
[ -f "$PACKAGES_GZ" ] || fail 'APT Packages.gz index is missing'
[ -f "$RELEASE" ] || fail 'APT Release file is missing'

assert_eq "$(dpkg-deb -f "$POOL_PACKAGE" Package)" 'pantheon-local-tools'
assert_eq "$(dpkg-deb -f "$POOL_PACKAGE" Version)" "$VERSION"
assert_eq "$(dpkg-deb -f "$POOL_PACKAGE" Architecture)" 'all'

grep -Fx 'Origin: Pantheon Local Tools' "$RELEASE" >/dev/null ||
  fail 'Release Origin is missing'
grep -Fx 'Suite: stable' "$RELEASE" >/dev/null ||
  fail 'Release Suite is missing'
grep -Fx 'Codename: stable' "$RELEASE" >/dev/null ||
  fail 'Release Codename is missing'
grep -Fx 'Architectures: all' "$RELEASE" >/dev/null ||
  fail 'Release Architectures is missing'
grep -Fx 'Components: main' "$RELEASE" >/dev/null ||
  fail 'Release Components is missing'
grep -F ' main/binary-all/Packages' "$RELEASE" >/dev/null ||
  fail 'Release does not cover Packages'
grep -F ' main/binary-all/Packages.gz' "$RELEASE" >/dev/null ||
  fail 'Release does not cover Packages.gz'

grep -Fx 'Package: pantheon-local-tools' "$PACKAGES" >/dev/null ||
  fail 'Packages index is missing package name'
grep -Fx "Version: $VERSION" "$PACKAGES" >/dev/null ||
  fail 'Packages index is missing current version'
grep -Fx 'Architecture: all' "$PACKAGES" >/dev/null ||
  fail 'Packages index is missing architecture'
grep -Fx "Filename: pool/main/p/pantheon-local-tools/pantheon-local-tools_${VERSION}_all.deb" \
  "$PACKAGES" >/dev/null ||
  fail 'Packages index has the wrong package path'

PACKAGE_SHA=$(sha256sum "$PACKAGE" | awk '{print $1}')
INDEX_SHA=$(awk '/^SHA256:/ {print $2; exit}' "$PACKAGES")
assert_eq "$INDEX_SHA" "$PACKAGE_SHA"

GNUPGHOME="$TMP_ROOT/gnupg"
export GNUPGHOME
mkdir -m 0700 "$GNUPGHOME"

gpg --batch --passphrase '' --quick-generate-key \
  'Pantheon Local Tools CI <ci@example.invalid>' \
  rsa2048 sign 1d >/dev/null 2>&1

SIGNING_KEY=$(
  gpg --batch --with-colons --list-secret-keys |
    awk -F: '$1 == "fpr" && !found { print $10; found = 1 }'
)

[ -n "$SIGNING_KEY" ] || fail 'ephemeral signing key fingerprint is missing'

bash "$REPO_ROOT/packaging/debian/sign-apt-repository.sh" \
  "$REPOSITORY_ONE" "$SIGNING_KEY" >/dev/null

INRELEASE="$REPOSITORY_ONE/dists/stable/InRelease"
RELEASE_GPG="$REPOSITORY_ONE/dists/stable/Release.gpg"
KEYRING="$REPOSITORY_ONE/pantheon-local-tools-archive-keyring.gpg"

[ -f "$INRELEASE" ] || fail 'InRelease is missing'
[ -f "$RELEASE_GPG" ] || fail 'Release.gpg is missing'
[ -s "$KEYRING" ] || fail 'public archive keyring is missing'

gpgv --keyring "$KEYRING" "$INRELEASE" >/dev/null 2>&1 ||
  fail 'InRelease does not verify with the exported keyring'

gpgv --keyring "$KEYRING" "$RELEASE_GPG" "$RELEASE" >/dev/null 2>&1 ||
  fail 'Release.gpg does not verify with the exported keyring'

APT_ROOT="$TMP_ROOT/apt"
mkdir -p "$APT_ROOT/lists/partial" "$APT_ROOT/cache/archives/partial"
touch "$APT_ROOT/status"

SOURCE_LIST="$TMP_ROOT/sources.list"
printf 'deb [signed-by=%s] file:%s stable main\n' \
  "$KEYRING" "$REPOSITORY_ONE" > "$SOURCE_LIST"

APT_OPTIONS=(
  -o "Dir::Etc::sourcelist=$SOURCE_LIST"
  -o "Dir::Etc::sourceparts=-"
  -o "Dir::State::lists=$APT_ROOT/lists"
  -o "Dir::State::status=$APT_ROOT/status"
  -o "Dir::Cache=$APT_ROOT/cache"
  -o "Dir::Cache::archives=$APT_ROOT/cache/archives"
  -o "Dir::Cache::pkgcache=$APT_ROOT/cache/pkgcache.bin"
  -o "Dir::Cache::srcpkgcache=$APT_ROOT/cache/srcpkgcache.bin"
  -o 'APT::Get::List-Cleanup=0'
)

apt-get "${APT_OPTIONS[@]}" update >/dev/null

CANDIDATE=$(
  apt-cache "${APT_OPTIONS[@]}" policy pantheon-local-tools |
    awk '/Candidate:/ && !found { print $2; found = 1 }'
)
assert_eq "$CANDIDATE" "$VERSION"

DOWNLOAD_ROOT="$TMP_ROOT/download"
mkdir -p "$DOWNLOAD_ROOT"

(
  cd "$DOWNLOAD_ROOT"
  apt-get "${APT_OPTIONS[@]}" download pantheon-local-tools >/dev/null 2>&1
)

DOWNLOADED_PACKAGE="$DOWNLOAD_ROOT/pantheon-local-tools_${VERSION}_all.deb"
[ -f "$DOWNLOADED_PACKAGE" ] || fail 'APT did not download the expected package'

cmp "$DOWNLOADED_PACKAGE" "$POOL_PACKAGE" ||
  fail 'APT-downloaded package differs from repository package'

cmp "$DOWNLOADED_PACKAGE" "$PACKAGE" ||
  fail 'APT-downloaded package differs from source package'

printf 'apt repository tests passed\n'
