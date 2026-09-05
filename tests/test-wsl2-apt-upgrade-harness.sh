#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
HARNESS="$ROOT_DIR/packaging/release/validate-wsl2-apt-upgrade.ps1"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local expected=$1
  grep -Fq -- "$expected" "$HARNESS" ||
    fail "harness is missing required contract text: $expected"
}

assert_not_contains() {
  local unexpected=$1
  if grep -Fq -- "$unexpected" "$HARNESS"; then
    fail "harness contains forbidden hard-coded/unsafe text: $unexpected"
  fi
}

[ -f "$HARNESS" ] || fail 'PowerShell harness is missing'

if LC_ALL=C grep -q $'\r' "$HARNESS"; then
  fail 'PowerShell harness must use LF line endings so the embedded Bash payload is stable'
fi

assert_contains "[string]\$FromVersion"
assert_contains "[string]\$ToVersion"
assert_contains "[string]\$DistroName"
assert_contains "[switch]\$ConfirmDisposableDistro"
assert_contains "[string]\$ExpectedOsId"
assert_contains "[string]\$ExpectedOsVersion"

assert_contains 'Refusing package validation without -ConfirmDisposableDistro'
assert_contains 'Refusing to target the current default WSL distribution'
assert_contains "'--',"
assert_contains 'PLT_EXPECTED_DISTRO='
assert_contains 'WSL_DISTRO_NAME'
assert_contains 'microsoft-standard-WSL2'
assert_contains 'validation state already exists'
assert_contains 'Evidence/state remains inside'
assert_contains 'No distro was unregistered.'

assert_contains 'install-apt.sh'
assert_contains 'APT_PRIMARY_FINGERPRINT'
assert_contains 'APT_REPOSITORY_URL'
assert_not_contains 'B75C45FA9E87AF56D7677F5785AF0D1C6E64C3F2'
assert_not_contains '0.1.1'
assert_not_contains '0.1.2'
assert_not_contains 'wsl.exe --unregister'

for rc in \
  .bashrc \
  .bash_profile \
  .bash_login \
  .profile \
  .zshenv \
  .zprofile \
  .zshrc \
  .zlogin \
  .zlogout
do
  assert_contains "$rc"
done

assert_contains "apt-get install --yes \"pantheon-local-tools=\$FROM_VERSION\""
assert_contains "apt-get install --yes --only-upgrade \"pantheon-local-tools=\$TO_VERSION\""
assert_contains "apt-get install --yes --reinstall \"pantheon-local-tools=\$TO_VERSION\""
assert_contains 'apt-get remove --yes pantheon-local-tools'
assert_contains 'assert_config_unchanged'
assert_contains 'assert_shell_unchanged'
assert_contains "[System.Text.Encoding]::UTF8.GetBytes(\$LinuxScript)"
assert_contains "[Convert]::ToBase64String(\$Bytes)"
assert_contains 'base64 -d | bash'
assert_contains 'Target identity: explicitly named non-default disposable WSL2 distro verified'

printf 'PASS: reusable WSL2 APT upgrade harness contract\n'
