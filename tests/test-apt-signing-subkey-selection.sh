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

for command_name in dpkg-deb dpkg-scanpackages gpg gpgv sha256sum sha512sum
do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'APT exact signing-subkey test skipped (%s unavailable)\n' \
      "$command_name"
    exit 0
  fi
done

PACKAGE=$(bash "$REPO_ROOT/packaging/debian/build-deb.sh" "$TMP_ROOT/package")
REPOSITORY="$TMP_ROOT/repository"
SOURCE_DATE_EPOCH=1787875200 \
  bash "$REPO_ROOT/packaging/debian/build-apt-repository.sh" \
    "$REPOSITORY" "$PACKAGE" >/dev/null

GNUPGHOME="$TMP_ROOT/gnupg"
export GNUPGHOME
mkdir -m 0700 "$GNUPGHOME"

PASSPHRASE='apt-exact-subkey-test'

gpg --batch --pinentry-mode loopback \
  --passphrase "$PASSPHRASE" \
  --quick-generate-key \
  'Pantheon Local Tools Rotation CI <ci@example.invalid>' \
  rsa2048 cert 1d >/dev/null 2>&1

PRIMARY_FINGERPRINT=$(
  gpg --batch --with-colons --list-secret-keys |
    awk -F: '$1 == "fpr" && !found { print $10; found = 1 }'
)
[ -n "$PRIMARY_FINGERPRINT" ] || fail 'rotation-test primary fingerprint is missing'

# Create two simultaneously usable signing subkeys. Exact selection must sign
# with the requested one rather than whichever subkey GPG would choose itself.
gpg --batch --pinentry-mode loopback \
  --passphrase "$PASSPHRASE" \
  --quick-add-key "$PRIMARY_FINGERPRINT" rsa2048 sign 1d >/dev/null 2>&1

gpg --batch --pinentry-mode loopback \
  --passphrase "$PASSPHRASE" \
  --quick-add-key "$PRIMARY_FINGERPRINT" rsa2048 sign 1d >/dev/null 2>&1

FIRST_SUBKEY=$(
  gpg --batch --with-colons --list-secret-keys "$PRIMARY_FINGERPRINT" |
    awk -F: '
      $1 == "ssb" { want_fpr = 1; next }
      want_fpr && $1 == "fpr" {
        print $10
        exit
      }
    '
)

SECOND_SUBKEY=$(
  gpg --batch --with-colons --list-secret-keys "$PRIMARY_FINGERPRINT" |
    awk -F: '
      $1 == "ssb" { want_fpr = 1; next }
      want_fpr && $1 == "fpr" {
        seen++
        if (seen == 2) {
          print $10
          exit
        }
        want_fpr = 0
      }
    '
)

[ -n "$FIRST_SUBKEY" ] || fail 'first signing subkey fingerprint is missing'
[ -n "$SECOND_SUBKEY" ] || fail 'second signing subkey fingerprint is missing'
[ "$FIRST_SUBKEY" != "$SECOND_SUBKEY" ] || fail 'signing subkeys are not distinct'

PANTHEON_LOCAL_APT_SIGNING_PASSPHRASE="$PASSPHRASE" \
PANTHEON_LOCAL_APT_EXACT_SIGNING_KEY=1 \
  bash "$REPO_ROOT/packaging/debian/sign-apt-repository.sh" \
    "$REPOSITORY" "$FIRST_SUBKEY" >/dev/null

KEYRING="$REPOSITORY/pantheon-local-tools-archive-keyring.gpg"
INRELEASE="$REPOSITORY/dists/stable/InRelease"

PUBLISHED_PRIMARY=$(
  gpg --batch --show-keys --with-colons "$KEYRING" |
    awk -F: '$1 == "fpr" && !found { print $10; found = 1 }'
)
assert_eq "$PUBLISHED_PRIMARY" "$PRIMARY_FINGERPRINT"

PUBLISHED_SUBKEYS=$(
  gpg --batch --show-keys --with-colons "$KEYRING" |
    awk -F: '$1 == "sub" { count++ } END { print count + 0 }'
)
assert_eq "$PUBLISHED_SUBKEYS" '2'

SIGNATURE_FINGERPRINT=$(
  gpgv --status-fd 1 --keyring "$KEYRING" "$INRELEASE" 2>/dev/null |
    awk '$2 == "VALIDSIG" && !found { print $3; found = 1 }'
)
assert_eq "$SIGNATURE_FINGERPRINT" "$FIRST_SUBKEY"

if PANTHEON_LOCAL_APT_EXACT_SIGNING_KEY=invalid \
  bash "$REPO_ROOT/packaging/debian/sign-apt-repository.sh" \
    "$REPOSITORY" "$FIRST_SUBKEY" >/dev/null 2>&1
then
  fail 'signer accepted an invalid exact-signing-key mode'
fi

printf 'APT exact signing-subkey tests passed\n'
