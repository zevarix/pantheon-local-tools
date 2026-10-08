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

# Prompting requires all three standard streams to be terminals. A redirected
# stdout/stderr or non-interactive stdin must never leave automation waiting.
assert_true plt_interact_can_prompt_for true true true
assert_false plt_interact_can_prompt_for false true true
assert_false plt_interact_can_prompt_for true false true
assert_false plt_interact_can_prompt_for true true false

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

plt_interact_choose 'Provider:' 2 'Auto' 'DDEV' 'Lando' <<< ''
assert_eq "$PLT_INTERACT_CHOICE" '2'
plt_interact_choose 'Provider:' '' 'Auto' 'DDEV' 'Lando' <<'EOF'
9
3
EOF
assert_eq "$PLT_INTERACT_CHOICE" '3'

# Shared prompt styling is optional and must not alter typed choice semantics.
# shellcheck disable=SC2317,SC2329 # Test-local terminal stub.
styled_prompt=$( (
  plt_term_style() { printf '[%s] %s' "$2" "$3"; }
  plt_interact_confirm 'Proceed?' <<< 'n'
) 2>&1 ) || :
case "$styled_prompt" in
  *'[active] Proceed? [y/N] '*) ;;
  *) fail 'confirmation did not use shared semantic terminal styling' ;;
esac

# shellcheck disable=SC2317,SC2329 # Test-local terminal stub.
styled_choice=$( (
  plt_term_style() { printf '[%s] %s' "$2" "$3"; }
  plt_interact_choose 'Provider:' 2 'Auto' 'DDEV' 'Lando' <<< ''
) 2>&1 ) || fail 'styled choice did not accept default'
case "$styled_choice" in
  *'[heading] Provider:'*'[active] Choice [2]: '*) ;;
  *) fail 'numbered choice did not use shared heading/active styles' ;;
esac

printf 'interaction tests passed\n'
