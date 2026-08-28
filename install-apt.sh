#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools APT installer'
APT_REPOSITORY_URL='https://zevarix.github.io/pantheon-local-tools'
APT_PRIMARY_FINGERPRINT='B75C45FA9E87AF56D7677F5785AF0D1C6E64C3F2'
APT_KEYRING_PATH='/etc/apt/keyrings/pantheon-local-tools.gpg'
APT_SOURCE_PATH='/etc/apt/sources.list.d/pantheon-local-tools.sources'

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

[ "$(uname -s)" = 'Linux' ] ||
  die 'the APT installer supports Debian-family Linux and WSL hosts only'

require_command apt-get
require_command awk
require_command curl
require_command id
require_command install
require_command mktemp

if [ "$(id -u)" -ne 0 ]; then
  require_command sudo
fi

if ! command -v gpg >/dev/null 2>&1; then
  printf 'Installing GnuPG prerequisite...\n'
  run_privileged apt-get update
  run_privileged apt-get install --yes ca-certificates gnupg
fi
require_command gpg

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

KEYRING="$TMP_ROOT/pantheon-local-tools-archive-keyring.gpg"
SOURCE_FILE="$TMP_ROOT/pantheon-local-tools.sources"

printf 'Downloading and verifying Pantheon Local Tools archive key...\n'
curl --fail --silent --show-error --location \
  "$APT_REPOSITORY_URL/pantheon-local-tools-archive-keyring.gpg" \
  --output "$KEYRING"

ACTUAL_FINGERPRINT=$(
  gpg --batch --show-keys --with-colons "$KEYRING" |
    awk -F: '$1 == "fpr" && !found { print $10; found = 1 }'
)

[ "$ACTUAL_FINGERPRINT" = "$APT_PRIMARY_FINGERPRINT" ] ||
  die "archive key fingerprint mismatch: $ACTUAL_FINGERPRINT"

cat > "$SOURCE_FILE" <<EOF
Types: deb
URIs: $APT_REPOSITORY_URL
Suites: stable
Components: main
Architectures: all
Signed-By: $APT_KEYRING_PATH
EOF

printf 'Configuring the signed APT repository...\n'
run_privileged install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
run_privileged install -m 0644 "$KEYRING" "$APT_KEYRING_PATH"
run_privileged install -m 0644 "$SOURCE_FILE" "$APT_SOURCE_PATH"

printf 'Installing Pantheon Local Tools...\n'
run_privileged apt-get update
run_privileged apt-get install --yes pantheon-local-tools

printf 'Pantheon Local Tools is installed.\n'
printf 'Run: pantheon-local --version\n'
printf 'Help: pantheon-local help\n'
