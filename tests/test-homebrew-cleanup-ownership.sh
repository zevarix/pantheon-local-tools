#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
UNDER_TEST="$REPO_ROOT/tests/test-homebrew-package.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "missing expected mock command: $2"; }
absent() { if grep -Fq -- "$2" "$1"; then fail "unexpected mock command: $2"; fi; }

mkdir -p "$TMP_ROOT/bin"
cat > "$TMP_ROOT/bin/brew" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$BREW_MOCK_LOG"
case "$1" in
  developer)
    option=''
    [ "$#" -lt 2 ] || option=$2
    case "$option" in
      off) rm -f "$BREW_MOCK_STATE/developer" ;;
      '') if [ -f "$BREW_MOCK_STATE/developer" ]; then echo enabled; else echo disabled; fi ;;
    esac ;;
  tap)
    [ ! -f "$BREW_MOCK_STATE/tap" ] || echo zevarix-ci/pantheon-local-tools-ci
    [ ! -f "$BREW_MOCK_STATE/core" ] || echo homebrew/core
    ;;
  list) [ -f "$BREW_MOCK_STATE/installed" ] ;;
  tap-new)
    touch "$BREW_MOCK_STATE/tap"
    if [ "$BREW_MOCK_SIDE_EFFECTS" = 1 ]; then
      touch "$BREW_MOCK_STATE/developer" "$BREW_MOCK_STATE/core"
    fi
    [ "$BREW_MOCK_FAIL_AT" != tap-new ] || exit 17
    ;;
  --repository)
    mkdir -p "$BREW_MOCK_STATE/tap-root/Formula"
    echo "$BREW_MOCK_STATE/tap-root" ;;
  style) [ "$BREW_MOCK_FAIL_AT" != style ] || exit 17 ;;
  install)
    touch "$BREW_MOCK_STATE/installed"
    [ "$BREW_MOCK_FAIL_AT" != install ] || exit 17 ;;
  test) exit 17 ;;
  uninstall) rm -f "$BREW_MOCK_STATE/installed" ;;
  untap)
    case "$2" in
      zevarix-ci/pantheon-local-tools-ci) rm -f "$BREW_MOCK_STATE/tap" ;;
      homebrew/core) rm -f "$BREW_MOCK_STATE/core" ;;
      *) exit 99 ;;
    esac ;;
  *) printf 'unexpected mocked brew invocation: %s\n' "$*" >&2; exit 99 ;;
esac
MOCK
chmod +x "$TMP_ROOT/bin/brew"

# The ownership fixture checks cleanup state, not Ruby syntax. Keep it portable
# to minimal Linux/WSL2 images without Ruby; the actual Homebrew package test
# still performs the real ruby -c check on supported macOS runners.
cat > "$TMP_ROOT/bin/ruby" <<'MOCK_RUBY'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 2 ] && [ "$1" = -c ] && [ -f "$2" ]
MOCK_RUBY
chmod +x "$TMP_ROOT/bin/ruby"

run_case() {
  local label=$1 failure=$2 dir="$TMP_ROOT/$1" rc=0
  mkdir -p "$dir/state" "$dir/home"
  case "$label" in
    existing-formula) touch "$dir/state/installed" ;;
    existing-tap) touch "$dir/state/tap" ;;
    preexisting-homebrew-state) touch "$dir/state/core" "$dir/state/developer" ;;
  esac
  BREW_MOCK_STATE="$dir/state" \
  BREW_MOCK_LOG="$dir/log" \
  BREW_MOCK_FAIL_AT="$failure" \
  BREW_MOCK_SIDE_EFFECTS="$TEST_SIDE_EFFECTS" \
  HOME="$dir/home" \
  PATH="$TMP_ROOT/bin:$PATH" \
    bash "$UNDER_TEST" >"$dir/output" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "$label unexpectedly passed"
  printf '%s\n' "$dir"
}

TEST_SIDE_EFFECTS=0
dir=$(run_case existing-formula none)
[ -f "$dir/state/installed" ] || fail 'pre-existing formula removed'
absent "$dir/log" 'uninstall'
absent "$dir/log" 'untap'
absent "$dir/log" 'developer off'

dir=$(run_case existing-tap none)
[ -f "$dir/state/tap" ] || fail 'pre-existing tap removed'
absent "$dir/log" 'uninstall'
absent "$dir/log" 'untap'
absent "$dir/log" 'developer off'

dir=$(run_case partial-tap tap-new)
[ ! -f "$dir/state/tap" ] || fail 'partial test-owned tap retained'
contains "$dir/log" 'untap zevarix-ci/pantheon-local-tools-ci'
absent "$dir/log" 'uninstall'

dir=$(run_case style-failure style)
[ ! -f "$dir/state/tap" ] || fail 'test-owned tap retained after style failure'
absent "$dir/log" 'uninstall'

dir=$(run_case partial-install install)
[ ! -f "$dir/state/tap" ] || fail 'test-owned tap retained after partial install'
[ ! -f "$dir/state/installed" ] || fail 'test-owned partial install retained'
contains "$dir/log" 'uninstall --force pantheon-local-tools'

dir=$(run_case after-install test)
[ ! -f "$dir/state/tap" ] || fail 'test-owned tap retained after brew test failure'
[ ! -f "$dir/state/installed" ] || fail 'test-owned install retained'
contains "$dir/log" 'uninstall --force pantheon-local-tools'

TEST_SIDE_EFFECTS=1
dir=$(run_case new-homebrew-state test)
[ ! -f "$dir/state/developer" ] || fail 'test-created developer mode retained'
[ ! -f "$dir/state/core" ] || fail 'test-created core tap retained'
contains "$dir/log" 'developer off'
contains "$dir/log" 'untap homebrew/core'

TEST_SIDE_EFFECTS=0
dir=$(run_case preexisting-homebrew-state test)
[ -f "$dir/state/developer" ] || fail 'pre-existing developer mode disabled'
[ -f "$dir/state/core" ] || fail 'pre-existing core tap removed'
absent "$dir/log" 'developer off'
absent "$dir/log" 'untap homebrew/core'

printf 'Homebrew cleanup ownership tests passed (mocked brew only)\n'
