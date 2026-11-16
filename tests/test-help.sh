#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected outputs to match"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected help to contain [$2]" ;; esac; }

help_output=$(bash "$CLI" help)
assert_eq "$help_output" "$(bash "$CLI" --help)"
assert_eq "$help_output" "$(bash "$CLI")"

for expected in \
  'pantheon-local config init [--root PATH] [--provider auto|ddev|lando]' \
  'pantheon-local config path' \
  'pantheon-local config get KEY' \
  'pantheon-local config set KEY VALUE' \
  'pantheon-local config unset KEY' \
  'pantheon-local config list' \
  'pantheon-local config tag get TAG' \
  'pantheon-local config tag set TAG DIRECTORY' \
  'pantheon-local config tag unset TAG' \
  'pantheon-local config tag list' \
  'pantheon-local config tag prefer set PREFERRED OTHER' \
  'pantheon-local config tag prefer unset PREFERRED OTHER' \
  'pantheon-local config tag prefer list' \
  'pantheon-local config tag profile get TAG PROPERTY' \
  'pantheon-local config tag profile set TAG PROPERTY VALUE' \
  'pantheon-local config tag profile unset TAG PROPERTY' \
  'pantheon-local config tag profile list [TAG]' \
  'pantheon-local config export [--provider ddev|lando] [--yes]' \
  'config-strategy  full-export or overlay-delta' \
  'config-path      Relative project configuration path such as config/sync' \
  'pantheon-local checkout SITE.dev [--dry-run] [--format default|json] [--record FILE]' \
  'pantheon-local checkout dev (--all | --tag TAG [--tag TAG ...]) [OPTIONS]' \
  'pantheon-local checkout sync SITE.dev [OPTIONS]' \
  'pantheon-local estate status SITE|--all|--tag TAG [OPTIONS]' \
  'pantheon-local doctor [--timing] [--format default|json] [--record FILE]' \
  'pantheon-local multidev SITE.ENV [--provider ddev|lando] [--group NAME] [--dry-run] [--start] [--setup] [--database-source ENV]' \
  'pantheon-local multidev create SITE.SOURCE NEW_ENV' \
  '[--provider ddev|lando] [--group NAME] [--dry-run] [--start] [--yes]' \
  '[--format default|json] [--record FILE]' \
  'pantheon-local setup [--provider ddev|lando] [--database-source ENV] [--dry-run]' \
  'pantheon-local readiness [--provider ddev|lando]' \
  'pantheon-local pull ENV [--database-only|--files-only] [--provider ddev|lando]' \
  'pantheon-local status [--format default|json] [--record FILE]' \
  'pantheon-local version' \
  'pantheon-local --version' \
  'auto   Detect from project configuration after checkout' \
  "pantheon-local config tag profile set 'Example Group' config-strategy full-export" \
  'pantheon-local config export --yes' \
  'pantheon-local multidev example.feature --dry-run' \
  'pantheon-local multidev create example.live feature1 --dry-run' \
  'pantheon-local setup --dry-run' \
  'pantheon-local readiness' \
  'pantheon-local pull test --database-only'
do
  assert_contains "$help_output" "$expected"
done
assert_contains "$help_output" 'Explicitly export tracked Drupal configuration'
assert_contains "$help_output" 'mutates project files'
assert_contains "$help_output" 'overlay-delta export is unsupported'
assert_contains "$help_output" 'Clone an already-existing Pantheon Multidev'
assert_contains "$help_output" 'Missing remote environments are never created implicitly.'
assert_contains "$help_output" 'Explicitly create a remote Pantheon Multidev'
assert_contains "$help_output" 'fails closed while owning validation is unavailable'

config_help=$(bash "$CLI" config help)
assert_contains "$config_help" 'pantheon-local config init [--root PATH] [--provider auto|ddev|lando]'
assert_contains "$config_help" 'pantheon-local config tag set TAG DIRECTORY'
assert_contains "$config_help" 'pantheon-local config tag profile set TAG PROPERTY VALUE'
assert_contains "$config_help" 'pantheon-local config export [--provider ddev|lando] [--yes]'
case "$config_help" in
  *'pantheon-local multidev SITE.ENV'*) fail 'config help must not show Multidev syntax' ;;
esac
assert_eq "$config_help" "$(bash "$CLI" config --help)"

tag_help=$(bash "$CLI" config tag help)
assert_contains "$tag_help" 'pantheon-local config tag profile list [TAG]'

init_help=$(bash "$CLI" config init --help)
assert_contains "$init_help" 'Usage: pantheon-local config init [--root PATH] [--provider auto|ddev|lando]'
assert_contains "$init_help" 'guided setup'

profile_help=$(bash "$CLI" config tag profile --help)
assert_contains "$profile_help" 'pantheon-local config tag profile get TAG PROPERTY'
assert_contains "$profile_help" 'config-strategy  full-export or overlay-delta'
assert_contains "$profile_help" 'Setting a profile property never creates a tag route.'

export_help=$(bash "$CLI" config export --help)
assert_contains "$export_help" 'pantheon-local config export [--provider ddev|lando] [--yes]'
assert_contains "$export_help" 'THIS COMMAND MUTATES PROJECT CONFIGURATION FILES.'
assert_contains "$export_help" 'configured export path to have no pre-existing Git changes'
assert_contains "$export_help" 'Run the normal full-export readiness inspection'
assert_contains "$export_help" 'Config Ignore'
assert_contains "$export_help" 'overlay-delta  Unsupported.'
assert_contains "$export_help" 'Required for non-interactive use.'
assert_contains "$export_help" 'PLT does not pass Drush --add or --commit'
assert_contains "$export_help" 'does not modify remote Pantheon environments'
assert_contains "$export_help" 'reports the resulting Git state'

checkout_help=$(bash "$CLI" checkout --help)
assert_contains "$checkout_help" 'pantheon-local checkout SITE.dev'
assert_contains "$checkout_help" 'pantheon-local checkout dev (--all | --tag TAG'
assert_contains "$checkout_help" 'pantheon-local checkout sync SITE.dev'
assert_contains "$checkout_help" 'canonical Pantheon Dev Git checkouts'
assert_contains "$checkout_help" 'Normal checkout never updates an existing checkout'
assert_contains "$checkout_help" '--format default|json'
assert_contains "$checkout_help" '--record FILE'

estate_help=$(bash "$CLI" estate status --help)
assert_contains "$estate_help" 'pantheon-local estate status SITE'
assert_contains "$estate_help" 'pantheon-local estate status --all'
assert_contains "$estate_help" 'Dev/Test/Live code identities'
assert_contains "$estate_help" 'inspection-only'
assert_contains "$estate_help" '--format default|json'
assert_contains "$estate_help" '--record FILE'

doctor_help=$(bash "$CLI" doctor --help)
assert_contains "$doctor_help" 'pantheon-local doctor [--timing] [--format default|json] [--record FILE]'
assert_contains "$doctor_help" 'Read-only diagnosis plus optional explicitly confirmed guided remediation.'
assert_contains "$doctor_help" 'PASS  Ready/healthy.'
assert_contains "$doctor_help" 'Diagnosis/report generation is read-only.'
assert_contains "$doctor_help" '--timing'
assert_contains "$doctor_help" '--format default'
assert_contains "$doctor_help" '--record FILE'

multidev_help=$(bash "$CLI" multidev --help)
assert_contains "$multidev_help" 'pantheon-local multidev SITE.ENV [--provider ddev|lando] [--group NAME] [--dry-run] [--start] [--setup] [--database-source ENV]'
assert_contains "$multidev_help" 'The remote environment must already exist'
assert_contains "$multidev_help" 'Requires --setup; replaces local database data.'
case "$multidev_help" in
  *'pantheon-local config init'*) fail 'Multidev help incorrectly displays configuration commands' ;;
esac
assert_eq "$multidev_help" "$(bash "$CLI" multidev -h)"
assert_eq "$multidev_help" "$(bash "$CLI" multidev help)"

multidev_create_help=$(bash "$CLI" multidev create --help)
assert_contains "$multidev_create_help" 'THIS COMMAND PERFORMS AN EXPLICIT REMOTE PANTHEON WRITE'
assert_contains "$multidev_create_help" 'database and files from this environment'
assert_contains "$multidev_create_help" 'at most 11 characters'
assert_contains "$multidev_create_help" 'Pantheon-reserved environment name'
assert_contains "$multidev_create_help" '--dry-run'
assert_contains "$multidev_create_help" '--start'
assert_contains "$multidev_create_help" '--yes'
assert_contains "$multidev_create_help" '--format default|json'
assert_contains "$multidev_create_help" '--record FILE'
assert_contains "$multidev_create_help" 'JSON is currently supported for --dry-run planning only.'
assert_contains "$multidev_create_help" 'Required for non-interactive creation.'
assert_contains "$multidev_create_help" 'If remote creation succeeds but local checkout/start fails'
assert_contains "$multidev_create_help" 'Multidev is deliberately preserved.'
assert_contains "$multidev_create_help" 'never deletes a Pantheon environment'

setup_help=$(bash "$CLI" setup --help)
assert_contains "$setup_help" 'pantheon-local setup [--provider ddev|lando] [--database-source ENV] [--dry-run]'
assert_contains "$setup_help" 'provider-owned composer install'
assert_contains "$setup_help" '--database-source ENV'
assert_contains "$setup_help" 'replaces local database data'
assert_contains "$setup_help" 'checkout-local PLT state'
assert_contains "$setup_help" 'Setup stops on the first failed step'
assert_contains "$setup_help" 'Fix the reported failure and run pantheon-local setup again.'

readiness_help=$(bash "$CLI" readiness --help)
assert_contains "$readiness_help" 'pantheon-local readiness [--provider ddev|lando]'
assert_contains "$readiness_help" 'full-export'
assert_contains "$readiness_help" 'overlay-delta'
assert_contains "$readiness_help" 'protected partial override set'
assert_contains "$readiness_help" 'Missing YAML'
assert_contains "$readiness_help" 'No provider-owned Drush command is invoked'
assert_contains "$readiness_help" 'No drush config:export / cex is run.'
assert_contains "$readiness_help" 'still exit 0 when inspection succeeds'
assert_contains "$readiness_help" 'Owning validation remains fail-closed'
assert_contains "$readiness_help" 'Config Ignore detection is advisory for full-export.'
assert_contains "$readiness_help" 'provider is not started or rebuilt'

pull_help=$(bash "$CLI" pull --help)
assert_contains "$pull_help" 'pantheon-local pull ENV [--database-only|--files-only] [--provider ddev|lando]'
assert_contains "$pull_help" 'without changing checked-out Git code'

status_help=$(bash "$CLI" status --help)
assert_contains "$status_help" 'pantheon-local status [--format default|json] [--record FILE]'
assert_contains "$status_help" 'without contacting Pantheon or starting a provider'
assert_contains "$status_help" 'Drupal bootstrap state is reported'
assert_contains "$status_help" 'JSON also includes the shared workflow lifecycle'
assert_contains "$status_help" '--format json'
assert_contains "$status_help" '--record FILE'

# Exercise every invocation in the public Help index, including new entries.
advertised_help=$(printf '%s\n' "$help_output" | sed -n '/^Help:/,$p' | grep '^  pantheon-local ')
[ -n "$advertised_help" ] || fail 'top-level Help index is empty'
while IFS= read -r invocation; do
  invocation=${invocation#  pantheon-local }
  read -r -a args <<< "$invocation"
  advertised_output=$(bash "$CLI" "${args[@]}") || fail "advertised help failed: $invocation"
  [ -n "$advertised_output" ] || fail "advertised help is empty: $invocation"
  case "$invocation" in
    help) assert_contains "$advertised_output" 'Pantheon Local Tools' ;;
    'config help') assert_contains "$advertised_output" 'pantheon-local config init' ;;
    'help config tag profile set') assert_contains "$advertised_output" 'pantheon-local config tag profile set TAG PROPERTY VALUE' ;;
    *)
      topic=${invocation% --help}
      assert_contains "$advertised_output" "pantheon-local $topic"
      ;;
  esac
done <<< "$advertised_help"

# Every public command/subcommand accepts -h and --help, including before
# required operands. Keep this matrix aligned with the public command index.
help_cases=$(cat <<'ROUTES'
shell|shell path
shell path|shell path
shell install|shell install
shell remove|shell remove
config|config init
config init|config init
config path|config path
config get|config get
config set|config set
config unset|config unset
config list|config list
config export|config export
config tag|config tag get
config tag get|config tag get
config tag set|config tag set
config tag unset|config tag unset
config tag list|config tag list
config tag prefer|config tag prefer set
config tag prefer set|config tag prefer set
config tag prefer unset|config tag prefer unset
config tag prefer list|config tag prefer list
config tag profile|config tag profile get
config tag profile get|config tag profile get
config tag profile set|config tag profile set
config tag profile unset|config tag profile unset
config tag profile list|config tag profile list
checkout|checkout SITE.dev
checkout sync|checkout sync SITE.dev
estate|estate status SITE
estate status|estate status SITE
doctor|doctor
multidev|multidev SITE.ENV
multidev create|multidev create SITE.SOURCE
provider|provider init
provider init|provider init
setup|setup
readiness|readiness
pull|pull ENV
status|status
version|version
--version|version
ROUTES
)

# Mock all external workflow tools. Help must not invoke them or create any
# persistent user config, shell startup file, checkout, or provider state.
help_fixture=$(mktemp -d)
trap 'rm -rf "$help_fixture"' EXIT
mkdir -p "$help_fixture/home" "$help_fixture/bin"
for external in git terminus ddev lando composer drush; do
  cat > "$help_fixture/bin/$external" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$0" >> "$HELP_FIXTURE_INVOCATIONS"
exit 66
STUB
  chmod +x "$help_fixture/bin/$external"
done

probe_help() {
  HOME="$help_fixture/home" \
  PANTHEON_LOCAL_CONFIG="$help_fixture/private/config" \
  HELP_FIXTURE_INVOCATIONS="$help_fixture/invocations" \
  PATH="$help_fixture/bin:$PATH" bash "$CLI" "$@"
}

checked=0
while IFS='|' read -r route expected; do
  [ -n "$route" ] || continue
  read -r -a route_args <<< "$route"
  expected_help=$(probe_help help "${route_args[@]}") || fail "help $route failed"
  assert_contains "$expected_help" "pantheon-local $expected"
  for flag in -h --help; do
    actual_help=$(probe_help "${route_args[@]}" "$flag") || fail "$route $flag failed"
    [ "$actual_help" = "$expected_help" ] || fail "$route $flag did not match help $route"
  done
  checked=$((checked + 1))
done <<< "$help_cases"
[ "$checked" -eq 41 ] || fail "expected 41 command routes, tested $checked"

# Help after fully specified mutating commands still performs no work.
for invocation in \
  'config set provider lando --help' \
  'config tag set Example-Group example-group --help' \
  'config tag prefer set Preferred Other --help' \
  'config tag profile set Example-Group config-strategy full-export --help' \
  'config export --yes --help' \
  'multidev example.feature --start --help' \
  'multidev example.feature --setup --database-source live --help' \
  'multidev create example.live feature1 --yes --help' \
  'checkout sync example.dev --help' \
  'shell install --shell bash --help'; do
  read -r -a args <<< "$invocation"
  probe_help "${args[@]}" >/dev/null || fail "unexpected help failure: $invocation"
done
[ ! -e "$help_fixture/invocations" ] || fail 'help attempted to invoke a workflow tool'
[ ! -e "$help_fixture/private" ] || fail 'help created user configuration'
[ ! -e "$help_fixture/home/.bashrc" ] || fail 'help modified shell startup'

# Terminal styling is optional and belongs to the shared presentation helper.
# Never emit escape codes into redirected output, NO_COLOR or TERM=dumb.
python3 - "$CLI" <<'PYTTY'
import errno
import os
import pty
import subprocess
import sys

cli = sys.argv[1]
def run_pty(env):
    master, slave = pty.openpty()
    try:
        child = subprocess.Popen(['bash', cli, 'multidev', '--help'],
                                 stdin=subprocess.DEVNULL, stdout=slave,
                                 stderr=slave, env=env)
        os.close(slave)
        slave = -1
        data = bytearray()
        while True:
            try:
                chunk = os.read(master, 65536)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            data.extend(chunk)
        if child.wait(timeout=10) != 0:
            raise SystemExit('FAIL: TTY help exited nonzero')
        return bytes(data)
    finally:
        os.close(master)
        if slave >= 0:
            os.close(slave)

env = os.environ.copy()
env['TERM'] = 'xterm-256color'
env.pop('NO_COLOR', None)
colored = run_pty(env)
if b'\x1b[' not in colored or b'Usage:' not in colored:
    raise SystemExit('FAIL: interactive help lost shared terminal styling')
for adjustment in ({'NO_COLOR': '1'}, {'TERM': 'dumb'}):
    plain_env = dict(env, **adjustment)
    plain = run_pty(plain_env)
    if b'\x1b[' in plain or b'Usage:' not in plain:
        raise SystemExit('FAIL: help ignored NO_COLOR or TERM=dumb')
plain = subprocess.run(['bash', cli, 'multidev', '--help'],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       env=env, check=True)
if b'\x1b[' in plain.stdout or plain.stderr:
    raise SystemExit('FAIL: redirected help contains ANSI or stderr')
PYTTY

printf 'help tests passed\n'
