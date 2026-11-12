#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# The deliberately unusual directory is provided as data, not shell code.
export NAV_TEST_ROOT="$TMP/start"
# shellcheck disable=SC2016 # Literal metacharacters must remain path data.
NAV_TEST_DEST="$TMP/checkout with spaces ; "'$(touch SHOULD_NOT_EXECUTE)'$'\n''second line'
export NAV_TEST_DEST
export NAV_TEST_LIB="$REPO_ROOT/shell/pantheon-local.sh"
export PANTHEON_LOCAL_SHELL_BIN="$TMP/fake-cli"
mkdir -p "$NAV_TEST_ROOT" "$NAV_TEST_DEST"

cat > "$PANTHEON_LOCAL_SHELL_BIN" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = multidev ]; then
  case " $* " in
    *" --dry-run "*) exit 0 ;;
  esac
  [ -n "${PANTHEON_LOCAL_CHDIR_FILE:-}" ] || exit 97
  printf '%s\0' "$NAV_TEST_DEST" > "$PANTHEON_LOCAL_CHDIR_FILE"
  exit "${FAKE_EXIT:-0}"
fi
[ -z "${PANTHEON_LOCAL_CHDIR_FILE:-}" ] || exit 98
printf 'other-command-ok\n'
FAKE
chmod +x "$PANTHEON_LOCAL_SHELL_BIN"

# shellcheck disable=SC2016 # Intentional shell script passed to Bash and zsh.
for user_shell in /bin/bash /bin/zsh; do
  "$user_shell" -c '
    set -eu
    . "$NAV_TEST_LIB"
    cd "$NAV_TEST_ROOT"
    [ "$(plt --version)" = "other-command-ok" ] || exit 1
    [ "$PWD" = "$NAV_TEST_ROOT" ] || exit 2

    # Successful existing Multidev and remote-create handoffs navigate.
    plt multidev example-site.feature1 >/dev/null
    [ "$PWD" = "$NAV_TEST_DEST" ] || exit 3
    cd "$NAV_TEST_ROOT"
    plt multidev create example-site.dev feature1 >/dev/null
    [ "$PWD" = "$NAV_TEST_DEST" ] || exit 4
    cd "$NAV_TEST_ROOT"
    pantheon-local multidev example-site.feature2 >/dev/null
    [ "$PWD" = "$NAV_TEST_DEST" ] || exit 5

    # A dry run must never change the terminal directory.
    cd "$NAV_TEST_ROOT"
    plt multidev example-site.feature3 --dry-run >/dev/null
    [ "$PWD" = "$NAV_TEST_ROOT" ] || exit 6

    # Failed work remains failed even if the child wrote a result path.
    FAKE_EXIT=19; export FAKE_EXIT
    if plt multidev example-site.feature4 >/dev/null; then exit 7; fi
    [ "$PWD" = "$NAV_TEST_ROOT" ] || exit 8
    unset FAKE_EXIT

    # A checkout can succeed while navigation itself becomes impossible.
    NAV_TEST_DEST="$NAV_TEST_ROOT/missing"; export NAV_TEST_DEST
    plt multidev example-site.feature5 >/dev/null 2>/dev/null
    [ "$PWD" = "$NAV_TEST_ROOT" ] || exit 9
  ' || fail "$user_shell integration test failed"
done

[ ! -e "$REPO_ROOT/SHOULD_NOT_EXECUTE" ] || fail 'unsafe command substitution ran in the repository'
[ ! -e "$TMP/SHOULD_NOT_EXECUTE" ] || fail 'unsafe path was evaluated as shell code'
[ ! -e "$NAV_TEST_ROOT/SHOULD_NOT_EXECUTE" ] || fail 'unsafe path was evaluated'
printf 'optional shell navigation tests passed (Bash/zsh)\n'
