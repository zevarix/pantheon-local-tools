#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_LIB="$REPO_ROOT/libexec/pantheon-local-output"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }

# shellcheck source=libexec/pantheon-local-output
. "$OUTPUT_LIB"

assert_eq "$PLT_STRUCTURED_SCHEMA_VERSION" '1'
assert_eq "$(plt_exit_category 0)" 'success'
assert_eq "$(plt_exit_category 10)" 'changed'
assert_eq "$(plt_exit_category 20)" 'no-targets'
assert_eq "$(plt_exit_category 30)" 'unsafe-local-state'
assert_eq "$(plt_exit_category 31)" 'ambiguous-configuration'
assert_eq "$(plt_exit_category 32)" 'authority-unavailable'
assert_eq "$(plt_exit_category 33)" 'verification-failed'
assert_eq "$(plt_exit_category 40)" 'operation-failed'
assert_eq "$(plt_exit_category 64)" 'usage-error'

special=$'quote" slash\\ tab\t newline\n carriage\r back\b form\f'
assert_eq "$(plt_json_string "$special")" '"quote\" slash\\ tab\t newline\n carriage\r back\b form\f"'
assert_eq "$(plt_json_nullable_string '')" 'null'
assert_eq "$(plt_json_nullable_string 'value')" '"value"'
assert_eq "$(plt_json_string_array example-b example-a 'example "quoted"')" '["example-b","example-a","example \"quoted\""]'

RECORD="$TMP_ROOT/result.json"
payload='{"schema_version":1,"record_type":"test","result":{"state":"current"}}'
plt_write_record "$RECORD" "$payload"
assert_eq "$(cat "$RECORD")" "$payload"

set +e
plt_write_record "$RECORD" '{"different":true}'
rc=$?
set -e
assert_eq "$rc" "$PLT_EXIT_UNSAFE_LOCAL_STATE"
assert_eq "$(cat "$RECORD")" "$payload"

MISSING="$TMP_ROOT/missing/result.json"
set +e
plt_write_record "$MISSING" "$payload"
rc=$?
set -e
assert_eq "$rc" "$PLT_EXIT_OPERATION_FAILED"

printf 'structured output tests passed\n'
