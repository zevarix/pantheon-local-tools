#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI="$REPO_ROOT/bin/pantheon-local"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file_has() { grep -Fqx -- "$2" "$1" || fail "expected line in $1: $2"; }

export HOME="$TMP/home" PANTHEON_LOCAL_CONFIG="$TMP/config"
unset ZDOTDIR BASH_ENV
mkdir -p "$HOME" "$TMP/bin" "$TMP/start"
export PATH="$TMP/bin:$PATH"
ln -s "$CLI" "$TMP/bin/pantheon-local"
ln -s "$CLI" "$TMP/bin/plt"

# Read-only CLI calls must not register any startup hook.
SHELL=/bin/zsh "$CLI" --version >/dev/null
SHELL=/bin/zsh "$CLI" shell path | grep -Fx "$REPO_ROOT/shell/pantheon-local.sh" >/dev/null || fail 'incorrect shell path'
SHELL=/bin/zsh "$CLI" config init --provider lando >/dev/null
[ ! -e "$HOME/.zshrc" ] || fail 'non-interactive call changed zsh startup'

# Existing user startup configuration is append-only and preserved.
printf 'export PLT_TEST_SENTINEL=preserved\n' > "$HOME/.zshrc"
before=$(cksum "$HOME/.zshrc" | awk '{print $1, $2}')
SHELL=/bin/zsh "$CLI" shell install --bin-dir "$TMP/bin" >/dev/null
assert_file_has "$HOME/.zshrc" '# >>> Pantheon Local Tools shell navigation >>>'
[ "$(grep -Fc '# >>> Pantheon Local Tools shell navigation >>>' "$HOME/.zshrc")" -eq 1 ] || fail 'duplicate hook'
SHELL=/bin/zsh "$CLI" shell install --bin-dir "$TMP/bin" >/dev/null
[ "$(grep -Fc '# >>> Pantheon Local Tools shell navigation >>>' "$HOME/.zshrc")" -eq 1 ] || fail 'reinstall duplicated hook'
grep -Fx 'export PLT_TEST_SENTINEL=preserved' "$HOME/.zshrc" >/dev/null || fail 'existing zsh data was overwritten'
[ "$before" != "$(cksum "$HOME/.zshrc" | awk '{print $1, $2}')" ] || fail 'hook was not appended'

# Installed shell integration is loaded by the shell automatically; no manual
# source command is used in these test sessions.
cat > "$TMP/fake-cli" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = multidev ] || exit 10
case " $* " in *" --dry-run "*) exit 0 ;; esac
[ -n "${PANTHEON_LOCAL_CHDIR_FILE:-}" ] || exit 11
printf '%s\0' "$NAV_TEST_DEST" > "$PANTHEON_LOCAL_CHDIR_FILE"
exit "${NAV_TEST_EXIT:-0}"
FAKE
chmod +x "$TMP/fake-cli"
export PANTHEON_LOCAL_SHELL_BIN="$TMP/fake-cli"
export NAV_TEST_START="$TMP/start"
# shellcheck disable=SC2016 # Literal shell metacharacters in path fixture.
NAV_TEST_DEST="$TMP/dest with spaces ; "'$(touch SHELL_MUST_NOT_EXECUTE)'$'\n''next line'
export NAV_TEST_DEST
mkdir -p "$NAV_TEST_DEST"

if [ -x /bin/zsh ]; then
  /bin/zsh -ic '
    [ "$PLT_TEST_SENTINEL" = preserved ] || exit 1
    whence -w plt | grep -F "function" >/dev/null || exit 2
    cd "$NAV_TEST_START"
    plt multidev example-site.feature1 >/dev/null
    [ "$PWD" = "$NAV_TEST_DEST" ] || exit 3
    cd "$NAV_TEST_START"
    plt multidev example-site.feature2 --dry-run >/dev/null
    [ "$PWD" = "$NAV_TEST_START" ] || exit 4
    NAV_TEST_EXIT=17; export NAV_TEST_EXIT
    if plt multidev example-site.feature2 >/dev/null; then exit 5; fi
    [ "$PWD" = "$NAV_TEST_START" ] || exit 6
  ' >/dev/null || fail 'zsh startup failed automatic directory navigation'
fi
[ ! -e "$TMP/SHELL_MUST_NOT_EXECUTE" ] || fail 'shell evaluated pathname as code'

# Safe startup handling: reject symlinks and malformed blocks without edits.
SHELL=/bin/zsh "$CLI" shell remove >/dev/null
assert_file_has "$HOME/.zshrc" 'export PLT_TEST_SENTINEL=preserved'
printf 'untouched\n' > "$TMP/external"
rm -f "$HOME/.zshrc"
ln -s "$TMP/external" "$HOME/.zshrc"
if SHELL=/bin/zsh "$CLI" shell install >/dev/null 2>&1; then fail 'symlink rc accepted'; fi
[ "$(cat "$TMP/external")" = untouched ] || fail 'symlink target modified'
rm "$HOME/.zshrc"
printf '# >>> Pantheon Local Tools shell navigation >>>\n' > "$HOME/.zshrc"
if SHELL=/bin/zsh "$CLI" shell install >/dev/null 2>&1; then fail 'partial managed block accepted'; fi
[ "$(wc -l < "$HOME/.zshrc")" -eq 1 ] || fail 'partial managed block changed'
rm "$HOME/.zshrc"

# Bash both interactive and login startup files; do not shadow an existing
# .profile by unnecessarily creating .bash_profile.
printf 'export PLT_BASH_SENTINEL=kept\n' > "$HOME/.profile"
SHELL=/bin/bash "$CLI" shell install --shell bash >/dev/null
[ -f "$HOME/.bashrc" ] || fail 'bashrc was not initialized'
[ ! -e "$HOME/.bash_profile" ] || fail 'bash_profile shadowed existing profile'
assert_file_has "$HOME/.profile" 'export PLT_BASH_SENTINEL=kept'
assert_file_has "$HOME/.bashrc" '# >>> Pantheon Local Tools shell navigation >>>'
if [ -x /bin/bash ]; then
  /bin/bash --noprofile --rcfile "$HOME/.bashrc" -ic '
    type -t plt | grep -Fx function >/dev/null || exit 1
    cd "$NAV_TEST_START"
    plt multidev example-site.feature3 >/dev/null
    [ "$PWD" = "$NAV_TEST_DEST" ] || exit 2
  ' >/dev/null 2>&1 || fail 'bash startup failed automatic navigation'
fi
SHELL=/bin/bash "$CLI" shell remove --shell bash >/dev/null
assert_file_has "$HOME/.profile" 'export PLT_BASH_SENTINEL=kept'
[ "$(grep -Fc '# >>> Pantheon Local Tools shell navigation >>>' "$HOME/.profile" || true)" -eq 0 ] || fail 'bash remove left hook'

# Portable installs register startup handling and PATH automatically.
PORTABLE="$TMP/portable"
mkdir -p "$PORTABLE"
HOME="$PORTABLE" SHELL=/bin/zsh PANTHEON_LOCAL_BIN_DIR="$TMP/portable's bin" \
  bash "$REPO_ROOT/install.sh" >/dev/null
[ -f "$PORTABLE/.zshrc" ] || fail 'portable installer did not register shell'
grep -F 'portable' "$PORTABLE/.zshrc" >/dev/null || fail 'portable PATH was not registered'
if [ -x /bin/zsh ]; then
  HOME="$PORTABLE" PATH="/usr/bin:/bin" /bin/zsh -ic '
    command -v pantheon-local >/dev/null || exit 1
    whence -w plt | grep -F function >/dev/null || exit 2
  ' >/dev/null 2>&1 || fail 'portable install did not initialize shell automatically'
fi
printf 'automatic shell startup and navigation tests passed\n'
