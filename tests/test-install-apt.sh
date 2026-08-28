#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  file=$1
  expected=$2
  grep -Fq -- "$expected" "$file" ||
    fail "expected $file to contain [$expected]"
}

MOCK_BIN="$TMP_ROOT/mock-bin"
CALL_LOG="$TMP_ROOT/calls.log"
CAPTURE_SOURCE="$TMP_ROOT/pantheon-local-tools.sources"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_UNAME:-Linux}"
EOF

cat > "$MOCK_BIN/id" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = '-u' ] || exit 64
printf '%s\n' "${MOCK_UID:-1000}"
EOF

cat > "$MOCK_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$CALL_LOG"
"$@"
EOF

cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
output=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--output' ]; then
    shift
    output=${1:-}
  fi
  shift || true
done
[ -n "$output" ] || exit 64
printf 'mock public keyring\n' > "$output"
printf 'curl keyring\n' >> "$CALL_LOG"
EOF

cat > "$MOCK_BIN/gpg" <<'EOF'
#!/usr/bin/env bash
printf 'pub:-:3072:1:0000000000000000:0:0:::::cSC::::::23::0:\n'
printf 'fpr:::::::::%s:\n' "${MOCK_FINGERPRINT:-B75C45FA9E87AF56D7677F5785AF0D1C6E64C3F2}"
EOF

cat > "$MOCK_BIN/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$CALL_LOG"
EOF

cat > "$MOCK_BIN/install" <<'EOF'
#!/usr/bin/env bash
printf 'install %s\n' "$*" >> "$CALL_LOG"
previous=''
last=''
for argument in "$@"; do
  previous=$last
  last=$argument
done
case "$last" in
  */pantheon-local-tools.sources)
    cp "$previous" "$CAPTURE_SOURCE"
    ;;
esac
EOF

chmod +x "$MOCK_BIN"/*
export CALL_LOG CAPTURE_SOURCE
export PATH="$MOCK_BIN:$PATH"

EXPECTED_FINGERPRINT='B75C45FA9E87AF56D7677F5785AF0D1C6E64C3F2'

install_output=$(bash "$REPO_ROOT/install-apt.sh")

case "$install_output" in
  *'Pantheon Local Tools is installed.'*) ;;
  *) fail 'installer did not report successful completion' ;;
esac
case "$install_output" in
  *'Run: pantheon-local --version'*) ;;
  *) fail 'installer did not point to a stable-safe version check' ;;
esac
case "$install_output" in
  *'Help: pantheon-local help'*) ;;
  *) fail 'installer did not point to in-tool help' ;;
esac
case "$install_output" in
  *'pantheon-local config init'*) fail 'installer advertised unreleased config init' ;;
esac

assert_file_contains "$CALL_LOG" 'curl keyring'
assert_file_contains "$CALL_LOG" 'sudo install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d'
assert_file_contains "$CALL_LOG" 'sudo install -m 0644'
assert_file_contains "$CALL_LOG" 'sudo apt-get update'
assert_file_contains "$CALL_LOG" 'sudo apt-get install --yes pantheon-local-tools'
assert_file_contains "$CAPTURE_SOURCE" 'Types: deb'
assert_file_contains "$CAPTURE_SOURCE" 'URIs: https://zevarix.github.io/pantheon-local-tools'
assert_file_contains "$CAPTURE_SOURCE" 'Suites: stable'
assert_file_contains "$CAPTURE_SOURCE" 'Components: main'
assert_file_contains "$CAPTURE_SOURCE" 'Architectures: all'
assert_file_contains "$CAPTURE_SOURCE" 'Signed-By: /etc/apt/keyrings/pantheon-local-tools.gpg'

# A fingerprint mismatch must fail before any privileged write or APT action.
: > "$CALL_LOG"
if MOCK_FINGERPRINT='0000000000000000000000000000000000000000' \
  bash "$REPO_ROOT/install-apt.sh" >/dev/null 2>&1; then
  fail 'installer accepted a mismatched archive fingerprint'
fi
if grep -Eq '^(sudo |apt-get |install )' "$CALL_LOG"; then
  fail 'fingerprint mismatch reached a privileged write or APT action'
fi

# The helper is intentionally Linux/APT-only; macOS users should use Homebrew.
: > "$CALL_LOG"
if MOCK_UNAME='Darwin' bash "$REPO_ROOT/install-apt.sh" >/dev/null 2>&1; then
  fail 'installer accepted an unsupported non-Linux host'
fi
[ ! -s "$CALL_LOG" ] || fail 'unsupported host executed external setup actions'

# Root execution must not require sudo.
: > "$CALL_LOG"
MOCK_UID='0' MOCK_FINGERPRINT="$EXPECTED_FINGERPRINT" \
  bash "$REPO_ROOT/install-apt.sh" >/dev/null
if grep -Eq '^sudo ' "$CALL_LOG"; then
  fail 'root execution unexpectedly invoked sudo'
fi
assert_file_contains "$CALL_LOG" 'apt-get update'
assert_file_contains "$CALL_LOG" 'apt-get install --yes pantheon-local-tools'

printf 'APT install tests passed\n'
