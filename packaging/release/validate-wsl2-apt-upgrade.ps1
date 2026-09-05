#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9][0-9A-Za-z.+:~_-]*$')]
    [string]$FromVersion,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9][0-9A-Za-z.+:~_-]*$')]
    [string]$ToVersion,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$DistroName,

    [switch]$ConfirmDisposableDistro,

    [ValidatePattern('^$|^[a-z0-9._-]+$')]
    [string]$ExpectedOsId = '',

    [ValidatePattern('^$|^[0-9A-Za-z._-]+$')]
    [string]$ExpectedOsVersion = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmDisposableDistro) {
    throw 'Refusing package validation without -ConfirmDisposableDistro. Use only a disposable WSL2 distribution/home.'
}

if ($FromVersion -eq $ToVersion) {
    throw 'FromVersion and ToVersion must identify different published package versions.'
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'wsl.exe was not found. Run this harness from Windows PowerShell 7 on a WSL-capable host.'
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$InstallAptPath = Join-Path $RepoRoot 'install-apt.sh'
if (-not (Test-Path -LiteralPath $InstallAptPath -PathType Leaf)) {
    throw "Cannot locate project-owned APT metadata at $InstallAptPath"
}

$InstallApt = Get-Content -LiteralPath $InstallAptPath -Raw
$FingerprintMatch = [regex]::Match(
    $InstallApt,
    "(?m)^APT_PRIMARY_FINGERPRINT='([A-F0-9]{40})'\s*$"
)
if (-not $FingerprintMatch.Success) {
    throw 'Could not resolve APT_PRIMARY_FINGERPRINT from install-apt.sh.'
}
$ExpectedFingerprint = $FingerprintMatch.Groups[1].Value

$RepositoryMatch = [regex]::Match(
    $InstallApt,
    "(?m)^APT_REPOSITORY_URL='([^']+)'\s*$"
)
if (-not $RepositoryMatch.Success) {
    throw 'Could not resolve APT_REPOSITORY_URL from install-apt.sh.'
}
$AptRepositoryUrl = $RepositoryMatch.Groups[1].Value

$VerboseOutput = & wsl.exe --list --verbose 2>&1
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect installed WSL distributions.'
}

$DefaultDistro = $null
$TargetFound = $false
$TargetVersion = $null

foreach ($RawLine in $VerboseOutput) {
    $Line = (($RawLine -replace "`0", '').Trim())
    if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
    }

    $IsDefault = $Line.StartsWith('*')
    if ($IsDefault) {
        $Line = $Line.Substring(1).TrimStart()
    }

    $Parts = $Line -split '\s+'
    if ($Parts.Count -lt 3) {
        continue
    }

    $Name = $Parts[0]
    $Version = $Parts[-1]

    if ($IsDefault) {
        $DefaultDistro = $Name
    }

    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($Name, $DistroName)) {
        $TargetFound = $true
        $TargetVersion = $Version
    }
}

if (-not $TargetFound) {
    throw "Disposable target distro '$DistroName' is not installed."
}

if ($TargetVersion -ne '2') {
    throw "Disposable target distro '$DistroName' is not WSL2 according to 'wsl.exe --list --verbose'."
}

if (
    $null -ne $DefaultDistro -and
    [System.StringComparer]::OrdinalIgnoreCase.Equals($DefaultDistro, $DistroName)
) {
    throw "Refusing to target the current default WSL distribution '$DistroName'. Create/select a separate disposable distro."
}

Write-Host '=== Pantheon Local Tools disposable WSL2 APT upgrade validation ==='
Write-Host "Target distro: $DistroName"
Write-Host "Upgrade: $FromVersion -> $ToVersion"
Write-Host 'The target must be disposable. The harness never unregisters a distribution.'
Write-Host

$LinuxScript = @'
set -Eeuo pipefail

FROM_VERSION=${PLT_FROM_VERSION:?}
TO_VERSION=${PLT_TO_VERSION:?}
EXPECTED_DISTRO=${PLT_EXPECTED_DISTRO:?}
EXPECTED_FINGERPRINT=${PLT_EXPECTED_FINGERPRINT:?}
APT_REPOSITORY_URL=${PLT_APT_REPOSITORY_URL:?}
EXPECTED_OS_ID=${PLT_EXPECTED_OS_ID:-}
EXPECTED_OS_VERSION=${PLT_EXPECTED_OS_VERSION:-}

TEST_USER='plt-test'
HOME_DIR='/home/plt-test'
STATE_ROOT='/root/pantheon-local-tools-wsl-validation'
STATE_DIR="$STATE_ROOT/${FROM_VERSION}-to-${TO_VERSION}"
SHELL_SNAPSHOT="$STATE_DIR/shell-before"
BASELINE_HASHES="$STATE_DIR/shell-baseline.sha256"
CONFIG="$HOME_DIR/.config/pantheon-local-tools/config"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

stage() {
  printf '\n=== %s ===\n' "$*"
}

assert_shell_unchanged() {
  local rc
  for rc in \
    .bashrc .bash_profile .bash_login .profile \
    .zshenv .zprofile .zshrc .zlogin .zlogout
  do
    cmp -s "$SHELL_SNAPSHOT/$rc" "$HOME_DIR/$rc" || \
      fail "shell startup file changed: $rc"
  done
}

assert_config_unchanged() {
  local current
  current=$(sha256sum "$CONFIG" | awk '{print $1}')
  [ "$current" = "$CONFIG_SHA" ] || fail 'user config bytes changed'
  [ "$(git config --file "$CONFIG" --get local.provider)" = 'ddev' ] || \
    fail 'user config provider changed'
}

trap 'printf "\nValidation stopped at line %s. Evidence/state remains inside %s.\n" "$LINENO" "$STATE_DIR" >&2' ERR

stage 'SAFETY BOUNDARY'

[ "${WSL_DISTRO_NAME:-}" = "$EXPECTED_DISTRO" ] || \
  fail "wrong WSL distro: expected $EXPECTED_DISTRO, got ${WSL_DISTRO_NAME:-unknown}"

[ "$(id -u)" -eq 0 ] || fail 'validation payload must run as root inside the disposable distro'

grep -qi 'microsoft-standard-WSL2' /proc/version || \
  fail 'target is not reporting a WSL2 kernel'

. /etc/os-release
printf 'distro identity: matched requested disposable target\n'
printf 'os: %s\n' "$PRETTY_NAME"
printf 'kernel: %s\n' "$(uname -r)"

if [ -n "$EXPECTED_OS_ID" ] && [ "$ID" != "$EXPECTED_OS_ID" ]; then
  fail "unexpected OS id: expected $EXPECTED_OS_ID, got $ID"
fi

if [ -n "$EXPECTED_OS_VERSION" ] && [ "$VERSION_ID" != "$EXPECTED_OS_VERSION" ]; then
  fail "unexpected OS version: expected $EXPECTED_OS_VERSION, got $VERSION_ID"
fi

if dpkg-query -W -f='${Status}\n' pantheon-local-tools 2>/dev/null |
   grep -qx 'install ok installed'
then
  fail 'pantheon-local-tools is already installed; use a clean disposable distro for release proof'
fi

[ ! -e /etc/apt/sources.list.d/pantheon-local-tools.sources ] || \
  fail 'Pantheon Local Tools APT source already exists; review the disposable distro before retrying'
[ ! -e /etc/apt/keyrings/pantheon-local-tools.gpg ] || \
  fail 'Pantheon Local Tools APT keyring already exists; review the disposable distro before retrying'
[ ! -e "$STATE_DIR" ] || \
  fail "validation state already exists at $STATE_DIR; preserve/review it before retrying"

mkdir -p "$STATE_DIR" "$SHELL_SNAPSHOT"

stage 'DISPOSABLE USER + SHELL BASELINE'

if ! id "$TEST_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$TEST_USER"
fi

mkdir -p "$HOME_DIR"

for rc in \
  .bashrc .bash_profile .bash_login .profile \
  .zshenv .zprofile .zshrc .zlogin .zlogout
do
  printf 'PLT-WSL-VALIDATION-SENTINEL:%s\n' "$rc" > "$HOME_DIR/$rc"
  cp -- "$HOME_DIR/$rc" "$SHELL_SNAPSHOT/$rc"
done

chown -R "$TEST_USER:$TEST_USER" "$HOME_DIR"

sha256sum \
  "$HOME_DIR/.bashrc" \
  "$HOME_DIR/.bash_profile" \
  "$HOME_DIR/.bash_login" \
  "$HOME_DIR/.profile" \
  "$HOME_DIR/.zshenv" \
  "$HOME_DIR/.zprofile" \
  "$HOME_DIR/.zshrc" \
  "$HOME_DIR/.zlogin" \
  "$HOME_DIR/.zlogout" \
  | tee "$BASELINE_HASHES"

assert_shell_unchanged
echo 'shell baseline: PASS'

stage 'APT PREREQUISITES'

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes ca-certificates curl gnupg

dpkg --compare-versions "$FROM_VERSION" lt "$TO_VERSION" || \
  fail "FromVersion must compare lower than ToVersion under Debian version semantics: $FROM_VERSION -> $TO_VERSION"

assert_shell_unchanged
echo 'shell files after prerequisite packages: PASS'

stage 'VERIFY ARCHIVE KEY'

KEYRING="$STATE_DIR/pantheon-local-tools-archive-keyring.gpg"

curl --fail --silent --show-error --location \
  "$APT_REPOSITORY_URL/pantheon-local-tools-archive-keyring.gpg" \
  --output "$KEYRING"

ACTUAL_FINGERPRINT=$(
  gpg --batch --show-keys --with-colons "$KEYRING" |
    awk -F: '$1 == "fpr" && !found { print $10; found = 1 }'
)

[ "$ACTUAL_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ] || \
  fail "archive fingerprint mismatch: $ACTUAL_FINGERPRINT"

printf 'archive fingerprint: %s\n' "$ACTUAL_FINGERPRINT"

install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
install -m 0644 \
  "$KEYRING" \
  /etc/apt/keyrings/pantheon-local-tools.gpg

cat > /etc/apt/sources.list.d/pantheon-local-tools.sources <<EOF
Types: deb
URIs: $APT_REPOSITORY_URL
Suites: stable
Components: main
Architectures: all
Signed-By: /etc/apt/keyrings/pantheon-local-tools.gpg
EOF

APT_UPDATE_OUTPUT=$(apt-get update 2>&1)
printf '%s\n' "$APT_UPDATE_OUTPUT"

case "$APT_UPDATE_OUTPUT" in
  *"doesn't support architecture"*)
    fail 'APT emitted an unsupported-architecture notice'
    ;;
esac

stage 'VERIFY PUBLISHED VERSIONS'

apt-cache policy pantheon-local-tools
apt-cache madison pantheon-local-tools

apt-cache madison pantheon-local-tools | awk '{print $3}' | grep -Fxq "$FROM_VERSION" || \
  fail "published repository does not expose $FROM_VERSION"

apt-cache madison pantheon-local-tools | awk '{print $3}' | grep -Fxq "$TO_VERSION" || \
  fail "published repository does not expose $TO_VERSION"

CANDIDATE=$(
  apt-cache policy pantheon-local-tools |
    awk '/Candidate:/ && !found { print $2; found = 1 }'
)

[ "$CANDIDATE" = "$TO_VERSION" ] || \
  fail "expected live candidate $TO_VERSION, got $CANDIDATE"

echo "candidate: $CANDIDATE"

stage "INSTALL PUBLISHED $FROM_VERSION"

apt-get install --yes "pantheon-local-tools=$FROM_VERSION"

[ "$(dpkg-query -W -f='${Version}' pantheon-local-tools)" = "$FROM_VERSION" ] || \
  fail "dpkg did not install $FROM_VERSION"

[ "$(/usr/bin/pantheon-local --version)" = "pantheon-local $FROM_VERSION" ] || \
  fail "CLI did not report $FROM_VERSION"

printf 'installed version: %s\n' "$FROM_VERSION"
assert_shell_unchanged
echo "shell files after $FROM_VERSION install: PASS"

stage 'CREATE USER-OWNED CONFIG'

install -d -o "$TEST_USER" -g "$TEST_USER" -m 0700 "$(dirname "$CONFIG")"

runuser -u "$TEST_USER" -- \
  env HOME="$HOME_DIR" PANTHEON_LOCAL_CONFIG="$CONFIG" \
  /usr/bin/pantheon-local config set provider ddev

PROVIDER=$(
  runuser -u "$TEST_USER" -- \
    env HOME="$HOME_DIR" PANTHEON_LOCAL_CONFIG="$CONFIG" \
    /usr/bin/pantheon-local config get provider
)

[ "$PROVIDER" = 'ddev' ] || fail 'user config did not read back provider ddev'
[ -f "$CONFIG" ] || fail 'user config file was not created'

CONFIG_SHA=$(sha256sum "$CONFIG" | awk '{print $1}')
CONFIG_OWNER=$(stat -c '%U:%G' "$CONFIG")

[ "$CONFIG_OWNER" = "$TEST_USER:$TEST_USER" ] || \
  fail "unexpected config owner: $CONFIG_OWNER"

printf 'config provider: %s\n' "$PROVIDER"
printf 'config owner: %s\n' "$CONFIG_OWNER"
printf 'config sha256: %s\n' "$CONFIG_SHA"

stage "APT UPGRADE $FROM_VERSION -> $TO_VERSION"

apt-get install --yes --only-upgrade "pantheon-local-tools=$TO_VERSION"

[ "$(dpkg-query -W -f='${Version}' pantheon-local-tools)" = "$TO_VERSION" ] || \
  fail "dpkg did not upgrade to $TO_VERSION"

[ "$(/usr/bin/pantheon-local --version)" = "pantheon-local $TO_VERSION" ] || \
  fail "CLI did not report $TO_VERSION"

assert_config_unchanged
assert_shell_unchanged

printf 'upgraded version: %s\n' "$TO_VERSION"
echo 'config after upgrade: PASS'
echo 'shell files after upgrade: PASS'

stage "REINSTALL $TO_VERSION"

apt-get install --yes --reinstall "pantheon-local-tools=$TO_VERSION"

[ "$(/usr/bin/pantheon-local --version)" = "pantheon-local $TO_VERSION" ] || \
  fail "CLI did not remain at $TO_VERSION after reinstall"

assert_config_unchanged
assert_shell_unchanged

echo 'reinstall: PASS'
echo 'config after reinstall: PASS'
echo 'shell files after reinstall: PASS'

stage 'REMOVE PACKAGE'

apt-get remove --yes pantheon-local-tools
hash -r

if dpkg-query -W -f='${Status}\n' pantheon-local-tools 2>/dev/null |
   grep -qx 'install ok installed'
then
  fail 'package remains installed after remove'
fi

[ ! -e /usr/bin/pantheon-local ] || fail '/usr/bin/pantheon-local remains after remove'
[ ! -e /usr/lib/pantheon-local-tools ] || \
  fail '/usr/lib/pantheon-local-tools remains after remove'

assert_config_unchanged
assert_shell_unchanged

echo 'remove: PASS'
echo 'user config after remove: PASS'
echo 'shell files after remove: PASS'

stage 'WRITE PUBLIC-SAFE EVIDENCE'

cat > "$STATE_DIR/evidence.txt" <<EOF
Pantheon Local Tools disposable WSL2 APT upgrade validation: PASS
Target identity: explicitly named non-default disposable WSL2 distro verified
OS: $PRETTY_NAME
Kernel: $(uname -r)
APT archive primary fingerprint: $ACTUAL_FINGERPRINT
Published versions present: $FROM_VERSION, $TO_VERSION
Live candidate: $TO_VERSION
Initial package install: $FROM_VERSION PASS
APT upgrade $FROM_VERSION -> $TO_VERSION: PASS
CLI version after upgrade: pantheon-local $TO_VERSION
User-owned config provider: ddev
User-owned config preservation: PASS
Bash/Zsh startup-file preservation: PASS
$TO_VERSION reinstall: PASS
Package remove: PASS
User-owned config after remove: PASS
EOF

cat "$STATE_DIR/evidence.txt"

stage 'CLEAN REPOSITORY CONFIG ONLY'

rm -f \
  /etc/apt/sources.list.d/pantheon-local-tools.sources \
  /etc/apt/keyrings/pantheon-local-tools.gpg

apt-get update >/dev/null

assert_config_unchanged
assert_shell_unchanged

echo
echo '=== WSL2 APT UPGRADE VALIDATION PASS ==='
echo "Evidence: $STATE_DIR/evidence.txt"
'@

$Bytes = [System.Text.Encoding]::UTF8.GetBytes($LinuxScript)
$Encoded = [Convert]::ToBase64String($Bytes)
$LinuxCommand = "printf '%s' '$Encoded' | base64 -d | bash"

$WslArguments = @(
    '-d', $DistroName,
    '-u', 'root',
    '--',
    'env',
    "PLT_FROM_VERSION=$FromVersion",
    "PLT_TO_VERSION=$ToVersion",
    "PLT_EXPECTED_DISTRO=$DistroName",
    "PLT_EXPECTED_FINGERPRINT=$ExpectedFingerprint",
    "PLT_APT_REPOSITORY_URL=$AptRepositoryUrl",
    "PLT_EXPECTED_OS_ID=$ExpectedOsId",
    "PLT_EXPECTED_OS_VERSION=$ExpectedOsVersion",
    'bash', '-lc', $LinuxCommand
)

& wsl.exe @WslArguments
if ($LASTEXITCODE -ne 0) {
    throw "WSL2 APT validation failed inside disposable distro '$DistroName'. Review retained evidence/state before retrying or deleting the distro."
}

$EvidencePath = "/root/pantheon-local-tools-wsl-validation/$FromVersion-to-$ToVersion/evidence.txt"

Write-Host
Write-Host '=== READ BACK PUBLIC-SAFE EVIDENCE ==='
& wsl.exe -d $DistroName -u root -- cat $EvidencePath
if ($LASTEXITCODE -ne 0) {
    throw 'Validation passed but evidence readback failed. Keep the disposable distro for inspection.'
}

Write-Host
Write-Host '=== COMPLETE ==='
Write-Host "Disposable distro retained for review: $DistroName"
Write-Host 'No distro was unregistered.'
