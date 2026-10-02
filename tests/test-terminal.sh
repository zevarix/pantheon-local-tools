#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
TERMINAL_LIB="$REPO_ROOT/libexec/pantheon-local-terminal"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_true() { "$@" || fail "expected success: $*"; }
assert_false() { if "$@"; then fail "expected failure: $*"; fi; }

[ -r "$TERMINAL_LIB" ] || fail 'terminal presentation helper is missing'
# shellcheck disable=SC1090 # Repository-local library under test.
. "$TERMINAL_LIB"

assert_true plt_term_interactive_for true xterm-256color
assert_false plt_term_interactive_for false xterm-256color
assert_false plt_term_interactive_for true dumb

assert_true plt_term_color_for true false
assert_false plt_term_color_for true true
assert_false plt_term_color_for false false

assert_eq "$(plt_term_style_raw false success 'ready')" 'ready'
assert_eq "$(plt_term_style 1 success 'ready')" 'ready'
assert_eq "$(plt_term_style_raw true success 'ready')" "$(printf '\033[32mready\033[0m')"
assert_eq "$(plt_term_style_raw true active 'working')" "$(printf '\033[96mworking\033[0m')"
assert_eq "$(plt_term_style_raw true warning 'review')" "$(printf '\033[33mreview\033[0m')"
assert_eq "$(plt_term_style_raw true failure 'blocked')" "$(printf '\033[31mblocked\033[0m')"
assert_eq "$(plt_term_style_raw true muted 'waiting')" "$(printf '\033[2mwaiting\033[0m')"

assert_eq "$(plt_term_status_glyph PASS)" '✓'
assert_eq "$(plt_term_status_glyph INFO)" '•'
assert_eq "$(plt_term_status_glyph WARN)" '!'
assert_eq "$(plt_term_status_glyph FAIL)" '×'
assert_eq "$(plt_term_status_glyph waiting)" '○'
assert_eq "$(plt_term_status_glyph skipped)" '–'

assert_eq "$(plt_term_status_style PASS)" success
assert_eq "$(plt_term_status_style INFO)" info
assert_eq "$(plt_term_status_style WARN)" warning
assert_eq "$(plt_term_status_style FAIL)" failure
assert_eq "$(plt_term_status_style waiting)" muted
assert_eq "$(plt_term_status_style active)" active

frames=''
i=0
while [ "$i" -lt 10 ]; do
  frames="$frames$(plt_term_spinner_frame "$i")"
  i=$((i + 1))
done
assert_eq "$frames" '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
assert_eq "$(plt_term_spinner_frame 10)" '⠋'

# This test process is non-interactive; cursor-control helpers must stay silent.
assert_eq "$(plt_term_rewind_current_line 1)" ''
assert_eq "$(plt_term_hide_cursor 1)" ''
assert_eq "$(plt_term_show_cursor 1)" ''
# shellcheck disable=SC2317,SC2329 # Test-local override is invoked by the sourced cursor helper.
assert_eq "$( ( plt_term_is_interactive() { return 0; }; plt_term_hide_cursor 1 ) )" "$(printf '\033[?25l')"
# shellcheck disable=SC2317,SC2329 # Test-local override is invoked by the sourced cursor helper.
assert_eq "$( ( plt_term_is_interactive() { return 0; }; plt_term_show_cursor 1 ) )" "$(printf '\033[?25h')"
assert_eq "$(plt_term_clear_current_line 1)" ''

printf 'terminal presentation tests passed\n'
