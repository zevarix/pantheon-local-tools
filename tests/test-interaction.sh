#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
INTERACTION_LIB="$REPO_ROOT/libexec/pantheon-local-interaction"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_true() { "$@" || fail "expected success: $*"; }
assert_false() { if "$@"; then fail "expected failure: $*"; fi; }

[ -r "$INTERACTION_LIB" ] || fail 'interaction helper is missing'
# shellcheck disable=SC1090 # Repository-local library under test.
. "$INTERACTION_LIB"

# CI/test process is non-interactive.
assert_false plt_interact_can_prompt

# Override only the TTY availability probe so the decision logic can be tested
# deterministically without depending on host PTY implementation details.
plt_interact_can_prompt() { return 0; }

assert_true plt_interact_confirm 'Proceed?' <<< 'y'
assert_true plt_interact_confirm 'Proceed?' <<< 'YES'
assert_false plt_interact_confirm 'Proceed?' <<< ''
assert_false plt_interact_confirm 'Proceed?' <<< 'n'

prompt_log=$(mktemp)
trap 'rm -f "$prompt_log"' EXIT HUP INT TERM
if plt_interact_confirm 'Proceed?' > /dev/null 2>"$prompt_log" <<'EOF'
maybe
y
EOF
then
  :
else
  fail 'confirmation did not accept y after invalid input'
fi
grep -F 'Please answer y or n.' "$prompt_log" >/dev/null 2>&1 || fail 'confirmation did not retry invalid input'

choice=$(plt_interact_choose 'Provider:' 2 'Auto' 'DDEV' 'Lando' <<< '')
assert_eq "$choice" '2'
choice=$(plt_interact_choose 'Provider:' '' 'Auto' 'DDEV' 'Lando' <<'EOF'
9
3
EOF
)
assert_eq "$choice" '3'

printf 'interaction tests passed\n'
