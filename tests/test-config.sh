#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
export HOME="$TMP_ROOT/home"
export PANTHEON_LOCAL_CONFIG="$TMP_ROOT/config/pantheon-local-tools/config"
mkdir -p "$HOME"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }

run_guided_init() {
  input=$1
  input_file="$TMP_ROOT/guided-input"
  command -v script >/dev/null 2>&1 || fail 'script command is required for guided config tests'
  printf '%b' "$input" > "$input_file"
  case "$(uname -s)" in
    Darwin)
      # BSD script may report a wrapper-level nonzero status at PTY EOF even
      # after the child completed. Assertions below verify output and state.
      script -q /dev/null bash "$CLI" config init < "$input_file" || true
      ;;
    *)
      script -q -c "bash \"$CLI\" config init" /dev/null < "$input_file" || true
      ;;
  esac
}

# The documented example must remain valid Git config data, not executable shell.
assert_eq "$(git config --file "$REPO_ROOT/config.example" --get local.provider)" 'auto'
if grep -Eq '(^|[[:space:]])(declare|source|eval)[[:space:]]' "$REPO_ROOT/config.example"; then
  fail 'config.example contains executable shell syntax'
fi

assert_eq "$(bash "$CLI" config path)" "$PANTHEON_LOCAL_CONFIG"
assert_eq "$(bash "$CLI" config get provider)" 'auto'
assert_eq "$(bash "$CLI" config get root)" "$HOME/sites/pantheon"

# No-option init is intentionally interactive and must not hang in automation.
non_tty_output="$TMP_ROOT/non-tty.out"
if bash "$CLI" config init </dev/null >"$non_tty_output" 2>&1; then
  fail 'config init without flags unexpectedly succeeded without a terminal'
fi
assert_contains "$(cat "$non_tty_output")" 'interactive config init requires a terminal'

# Flags provide the concise, non-interactive path and may be supplied independently.
rm -f "$PANTHEON_LOCAL_CONFIG"
output=$(bash "$CLI" config init --provider ddev)
assert_contains "$output" 'Configuration saved.'
assert_contains "$output" 'provider=ddev'
assert_eq "$(bash "$CLI" config get provider)" 'ddev'
assert_eq "$(bash "$CLI" config get root)" "$HOME/sites/pantheon"

bash "$CLI" config init --root "$HOME/Flag Root" >/dev/null
assert_eq "$(bash "$CLI" config get root)" "$HOME/Flag Root"
assert_eq "$(bash "$CLI" config get provider)" 'ddev'

bash "$CLI" config init --root "$HOME/Both Root" --provider lando >/dev/null
assert_eq "$(bash "$CLI" config get root)" "$HOME/Both Root"
assert_eq "$(bash "$CLI" config get provider)" 'lando'

# Validate all requested values before writing any of them.
if bash "$CLI" config init --root "$HOME/Must Not Persist" --provider nope >/dev/null 2>&1; then
  fail 'config init accepted an invalid provider'
fi
assert_eq "$(bash "$CLI" config get root)" "$HOME/Both Root"
assert_eq "$(bash "$CLI" config get provider)" 'lando'

# Guided setup uses effective defaults/current values and confirms before writing.
rm -f "$PANTHEON_LOCAL_CONFIG"
output=$(run_guided_init '\n\n\n')
assert_contains "$output" 'Auto - use the project DDEV or Lando configuration (recommended)'
assert_contains "$output" 'Configuration saved.'
assert_eq "$(bash "$CLI" config get root)" "$HOME/sites/pantheon"
assert_eq "$(bash "$CLI" config get provider)" 'auto'

rm -f "$PANTHEON_LOCAL_CONFIG"
run_guided_init '\n2\n\n' >/dev/null
assert_eq "$(bash "$CLI" config get provider)" 'ddev'

rm -f "$PANTHEON_LOCAL_CONFIG"
run_guided_init '\n3\n\n' >/dev/null
assert_eq "$(bash "$CLI" config get provider)" 'lando'

bash "$CLI" config set root "$HOME/Keep Root"
bash "$CLI" config set provider auto
output=$(run_guided_init "$HOME/Cancelled Root\n2\nn\n")
assert_contains "$output" 'Configuration not changed.'
assert_eq "$(bash "$CLI" config get root)" "$HOME/Keep Root"
assert_eq "$(bash "$CLI" config get provider)" 'auto'

tilde='~'
bash "$CLI" config set root "$tilde/Pantheon Sites"
assert_eq "$(bash "$CLI" config get root)" "$HOME/Pantheon Sites"

# WSL uses Linux paths; /mnt/<drive>/... is accepted while native Windows paths are rejected.
bash "$CLI" config set root '/mnt/c/Users/example/Pantheon Sites'
assert_eq "$(bash "$CLI" config get root)" '/mnt/c/Users/example/Pantheon Sites'
if bash "$CLI" config set root 'C:\Users\example\Pantheon' >/dev/null 2>&1; then
  fail 'native Windows root path was accepted'
fi
if bash "$CLI" config set root 'relative/path' >/dev/null 2>&1; then
  fail 'relative root path was accepted'
fi

bash "$CLI" config set root "$HOME/Pantheon Sites"
bash "$CLI" config set provider lando
assert_eq "$(bash "$CLI" config get provider)" 'lando'
if bash "$CLI" config set provider nope >/dev/null 2>&1; then fail 'invalid provider was accepted'; fi

bash "$CLI" config tag set 'Client Sites.v2' 'clients/main'
assert_eq "$(bash "$CLI" config tag get 'Client Sites.v2')" 'clients/main'
assert_contains "$(bash "$CLI" config tag list)" 'Client Sites.v2=clients/main'

if bash "$CLI" config tag set Unsafe '/absolute/path' >/dev/null 2>&1; then fail 'absolute tag directory was accepted'; fi
if bash "$CLI" config tag set Unsafe '../escape' >/dev/null 2>&1; then fail '.. tag directory was accepted'; fi
if bash "$CLI" config tag set Unsafe 'foo\\bar' >/dev/null 2>&1; then fail 'backslash tag directory was accepted'; fi

output=$(bash "$CLI" config list)
assert_contains "$output" "root=$HOME/Pantheon Sites"
assert_contains "$output" 'provider=lando'
assert_contains "$output" 'tag.Client Sites.v2=clients/main'
if printf '%s\n' "$output" | grep -q 'site-prefix'; then fail 'removed site-prefix setting is still exposed'; fi

bash "$CLI" config unset provider
assert_eq "$(bash "$CLI" config get provider)" 'auto'
bash "$CLI" config tag unset 'Client Sites.v2'
assert_eq "$(bash "$CLI" config tag list)" ''

printf 'config tests passed\n'
