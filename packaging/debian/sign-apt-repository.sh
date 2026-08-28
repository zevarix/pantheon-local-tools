#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools APT repository signer'

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

[ "$#" -eq 2 ] ||
  die 'usage: sign-apt-repository.sh REPOSITORY_DIR SIGNING_KEY_FINGERPRINT'

REPOSITORY_DIR=$1
SIGNING_KEY=$2

require_command gpg
require_command gpgv
require_command grep

[ -d "$REPOSITORY_DIR" ] ||
  die "repository directory not found: $REPOSITORY_DIR"

REPOSITORY_DIR=$(cd "$REPOSITORY_DIR" && pwd)
RELEASE="$REPOSITORY_DIR/dists/stable/Release"
INRELEASE="$REPOSITORY_DIR/dists/stable/InRelease"
RELEASE_GPG="$REPOSITORY_DIR/dists/stable/Release.gpg"
KEYRING="$REPOSITORY_DIR/pantheon-local-tools-archive-keyring.gpg"

[ -f "$RELEASE" ] || die "Release file not found: $RELEASE"

printf '%s\n' "$SIGNING_KEY" |
  grep -Eq '^[0-9A-Fa-f]{40}([0-9A-Fa-f]{24})?$' ||
  die 'signing key must be a full 40- or 64-hex fingerprint'

gpg --batch --list-secret-keys "$SIGNING_KEY" >/dev/null 2>&1 ||
  die 'signing secret key is not available'

rm -f "$INRELEASE" "$RELEASE_GPG" "$KEYRING"

gpg_sign() {
  output=$1
  shift

  if [ -n "${PANTHEON_LOCAL_APT_SIGNING_PASSPHRASE:-}" ]; then
    printf '%s' "$PANTHEON_LOCAL_APT_SIGNING_PASSPHRASE" |
      gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
        --local-user "$SIGNING_KEY" "$@" --output "$output" "$RELEASE"
  else
    gpg --batch --yes --local-user "$SIGNING_KEY" \
      "$@" --output "$output" "$RELEASE"
  fi
}

gpg_sign "$INRELEASE" --armor --clearsign
gpg_sign "$RELEASE_GPG" --armor --detach-sign

gpg --batch --yes --export "$SIGNING_KEY" > "$KEYRING"
[ -s "$KEYRING" ] || die 'public archive key export is empty'

chmod 0644 "$INRELEASE" "$RELEASE_GPG" "$KEYRING"

gpgv --keyring "$KEYRING" "$INRELEASE" >/dev/null 2>&1 ||
  die 'InRelease verification failed'

gpgv --keyring "$KEYRING" "$RELEASE_GPG" "$RELEASE" >/dev/null 2>&1 ||
  die 'Release.gpg verification failed'

printf '%s\n' "$REPOSITORY_DIR"
