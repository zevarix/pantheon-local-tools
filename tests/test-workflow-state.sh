#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
HELPER="$REPO_ROOT/libexec/pantheon-local-workflow-state"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
STATE="$TMP_ROOT/state"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }

git config --file "$STATE" pantheon.site example-site

"$HELPER" record "$STATE" setup built-in apply in-progress provider-start \
  'rerun pantheon-local setup after resolving the reported failure'

assert_eq "$("$HELPER" get "$STATE" setup schema)" '1'
assert_eq "$("$HELPER" get "$STATE" setup kind)" 'built-in'
assert_eq "$("$HELPER" get "$STATE" setup phase)" 'apply'
assert_eq "$("$HELPER" get "$STATE" setup status)" 'in-progress'
assert_eq "$("$HELPER" get "$STATE" setup step)" 'provider-start'
assert_eq "$("$HELPER" get "$STATE" setup safe-next-action)" \
  'rerun pantheon-local setup after resolving the reported failure'
[ -n "$("$HELPER" get "$STATE" setup updated-at)" ] || fail 'updated-at was not recorded'
assert_eq "$(git config --file "$STATE" --get pantheon.site)" 'example-site'

"$HELPER" record "$STATE" setup built-in complete complete complete none
assert_eq "$("$HELPER" get "$STATE" setup phase)" 'complete'
assert_eq "$("$HELPER" get "$STATE" setup status)" 'complete'
assert_eq "$("$HELPER" get "$STATE" setup step)" 'complete'
assert_eq "$("$HELPER" get "$STATE" setup safe-next-action)" 'none'

"$HELPER" record "$STATE" config-export built-in plan planned preflight review
assert_eq "$("$HELPER" get "$STATE" config-export status)" 'planned'
assert_eq "$("$HELPER" get "$STATE" setup status)" 'complete'

before=$(cat "$STATE")
if "$HELPER" record "$STATE" 'Bad Workflow' built-in apply failed step retry >/dev/null 2>&1; then
  fail 'invalid workflow identifier was accepted'
fi
assert_eq "$(cat "$STATE")" "$before"

if "$HELPER" record "$STATE" setup upstream apply failed step retry >/dev/null 2>&1; then
  fail 'invalid workflow kind was accepted'
fi

if "$HELPER" record "$STATE" setup built-in mutate failed step retry >/dev/null 2>&1; then
  fail 'invalid workflow phase was accepted'
fi

if "$HELPER" record "$STATE" setup built-in apply uncertain step retry >/dev/null 2>&1; then
  fail 'invalid workflow status was accepted'
fi

if "$HELPER" get "$STATE" setup unknown >/dev/null 2>&1; then
  fail 'unsupported workflow property was accepted'
fi

printf 'workflow state tests passed\n'
