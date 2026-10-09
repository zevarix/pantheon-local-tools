#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI=${CLI:-"$REPO_ROOT/bin/pantheon-local"}
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
ORIGINAL_PATH=$PATH

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected output to contain [$2], got [$1]" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "expected output not to contain [$2], got [$1]" ;; *) ;; esac; }
assert_file_not_contains() { if [ -f "$1" ] && grep -F "$2" "$1" >/dev/null 2>&1; then fail "expected $1 not to contain [$2]"; fi; }
assert_file_contains() { grep -F "$2" "$1" >/dev/null 2>&1 || fail "expected $1 to contain [$2]"; }
assert_file_matches() { grep -E "$2" "$1" >/dev/null 2>&1 || fail "expected $1 to match [$2]"; }

run_doctor_pty() {
  input=$1
  shift
  command -v python3 >/dev/null 2>&1 || fail 'python3 is required for doctor PTY tests'
  python3 - "$CLI" "$input" "$@" <<'PY'
import errno
import os
import pty
import sys

cli = sys.argv[1]
data = sys.argv[2].encode()
args = sys.argv[3:]
env = os.environ.copy()
env['TERM'] = 'xterm-256color'
pid, fd = pty.fork()
if pid == 0:
    os.execve('/bin/bash', ['bash', cli, 'doctor', *args], env)

cols = int(os.environ.get('DOCTOR_TEST_TTY_COLS', '0'))
if cols:
    import fcntl
    import struct
    import termios
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 30, cols, 0, 0))

while data:
    written = os.write(fd, data)
    data = data[written:]

while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError as exc:
        if exc.errno == errno.EIO:
            break
        raise
    if not chunk:
        break
    sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()

_, status = os.waitpid(pid, 0)
if os.WIFEXITED(status):
    raise SystemExit(os.WEXITSTATUS(status))
if os.WIFSIGNALED(status):
    raise SystemExit(128 + os.WTERMSIG(status))
raise SystemExit(1)
PY
}

scenario_init() {
  local name=$1
  SCENARIO="$TMP_ROOT/$name"
  HOME="$SCENARIO/home"
  PANTHEON_LOCAL_CONFIG="$SCENARIO/config/pantheon-local-tools/config"
  MOCK_BIN="$SCENARIO/bin"
  MOCK_DATA="$SCENARIO/data"
  LOCAL_ROOT="$SCENARIO/sites"
  MOCK_TERMINUS_LOG="$SCENARIO/terminus.log"
  MOCK_PROVIDER_LOG="$SCENARIO/provider.log"
  export HOME PANTHEON_LOCAL_CONFIG MOCK_DATA MOCK_TERMINUS_LOG MOCK_PROVIDER_LOG
  unset MOCK_AUTH_FAIL MOCK_SITE_LIST_FAIL MOCK_ENV_FAIL_SITE MOCK_TAG_FAIL_SITE MOCK_CONNECTION_FAIL_SITE MOCK_BLOCK_ENV_SITE MOCK_BLOCK_READY_FILE MOCK_ENV_DELAY_SITE MOCK_ENV_DELAY_SECONDS MOCK_SSH_GIT_SITE GIT_SSH_COMMAND
  TMPDIR="$SCENARIO/tmp"
  export TMPDIR
  mkdir -p "$HOME" "$MOCK_BIN" "$MOCK_DATA" "$LOCAL_ROOT" "$TMPDIR"
  : > "$MOCK_TERMINUS_LOG"
  : > "$MOCK_PROVIDER_LOG"
  PATH="$MOCK_BIN:$ORIGINAL_PATH"
  export PATH
  create_mock_terminus
  create_mock_provider ddev
  create_mock_provider lando
}

create_mock_terminus() {
  cat > "$MOCK_BIN/terminus" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
line='terminus'
for arg in "$@"; do line="$line|$arg"; done
printf '%s\n' "$line" >> "${MOCK_TERMINUS_LOG:?}"
case "${1:-}" in
  auth:whoami)
    [ "${MOCK_AUTH_FAIL:-false}" != true ] || exit 9
    printf '%s\n' 'developer@example.com'
    ;;
  site:list)
    [ "${MOCK_SITE_LIST_FAIL:-false}" != true ] || exit 9
    [ "${2:-}" = '--format=list' ] || exit 2
    [ "${3:-}" = '--field=name' ] || exit 2
    cat "${MOCK_DATA:?}/sites"
    ;;
  env:list)
    site=${2:?}
    [ "$site" != "${MOCK_ENV_FAIL_SITE:-}" ] || exit 9
    [ "${3:-}" = '--format=list' ] || exit 2
    [ "${4:-}" = '--field=id' ] || exit 2
    if [ "$site" = "${MOCK_ENV_DELAY_SITE:-}" ]; then
      sleep "${MOCK_ENV_DELAY_SECONDS:-2}"
    fi
    if [ "$site" = "${MOCK_BLOCK_ENV_SITE:-}" ]; then
      [ -n "${MOCK_BLOCK_READY_FILE:-}" ] || exit 2
      : > "$MOCK_BLOCK_READY_FILE"
      sleep 30
    fi
    cat "${MOCK_DATA:?}/$site.envs"
    ;;
  site:info)
    site=${2:?}
    [ "$site" != "${MOCK_TAG_FAIL_SITE:-}" ] || exit 9
    case "${3:-}" in
      --field=organization) printf '%s\n' 'Example Org' ;;
      --field=framework) printf '%s\n' drupal8 ;;
      --field=id) printf '%s\n' aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee ;;
      *) exit 2 ;;
    esac
    ;;
  tag:list)
    site=${2:?}
    [ "$site" != "${MOCK_TAG_FAIL_SITE:-}" ] || exit 9
    [ "${4:-}" = '--format=list' ] || exit 2
    cat "${MOCK_DATA:?}/$site.tags"
    ;;
  connection:info)
    target=${2:?}
    [ "${3:-}" = '--field=git_url' ] || exit 2
    site=${target%.dev}
    [ "$site" != "${MOCK_CONNECTION_FAIL_SITE:-}" ] || exit 9
    if [ "$site" = "${MOCK_SSH_GIT_SITE:-}" ]; then
      printf '%s\n' 'ssh://git@example.invalid:2222/example.git'
    else
      cat "${MOCK_DATA:?}/$site.git-url"
    fi
    ;;
  *) printf 'unexpected terminus command: %s\n' "${1:-}" >&2; exit 2 ;;
esac
MOCK
  chmod +x "$MOCK_BIN/terminus"
}

create_mock_provider() {
  local provider=$1
  cat > "$MOCK_BIN/$provider" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$0 $*" >> "${MOCK_PROVIDER_LOG:?}"
if [ "${MOCK_DDEV_CONFIG_ENABLED:-false}" = true ] && [ "${1:-}" = config ]; then
  mkdir -p .ddev/providers
  printf 'name: example-site\ntype: drupal11\ndocroot: web\n' > .ddev/config.yaml
  printf '# Pantheon provider fixture\n' > .ddev/providers/pantheon.yaml
  exit 0
fi
exit 9
MOCK
  chmod +x "$MOCK_BIN/$provider"
}

create_remote() {
  local site=$1 tags=$2 provider=${3:-ddev} source bare
  source="$MOCK_DATA/$site-source"
  bare="$MOCK_DATA/$site.git"
  mkdir -p "$source"
  git -C "$source" init -q
  git -C "$source" config user.name 'Test User'
  git -C "$source" config user.email 'test@example.com'
  printf '%s\n' "$site" > "$source/README.md"
  case "$provider" in
    ddev) mkdir -p "$source/.ddev"; printf 'name: %s\ntype: drupal11\n' "$site" > "$source/.ddev/config.yaml" ;;
    lando) printf 'name: %s\nrecipe: pantheon\n' "$site" > "$source/.lando.yml" ;;
    none)
      mkdir -p "$source/web"
      printf '<?php\n' > "$source/web/index.php"
      printf '%s\n' '{"require":{"drupal/core-recommended":"^11.4"}}' > "$source/composer.json"
      ;;
  esac
  git -C "$source" add .
  git -C "$source" commit -qm 'Initial Dev'
  git -C "$source" branch -M master
  git clone -q --bare "$source" "$bare"
  git --git-dir="$bare" symbolic-ref HEAD refs/heads/master
  printf '%s\n' "$tags" > "$MOCK_DATA/$site.tags"
  printf '%s\n' dev test live > "$MOCK_DATA/$site.envs"
  printf '%s\n' "$bare" > "$MOCK_DATA/$site.git-url"
}

set_sites() { printf '%s\n' "$@" > "$MOCK_DATA/sites"; }

create_checkout() {
  local site=$1 route=$2 provider=${3:-ddev} dest
  dest="$LOCAL_ROOT/$route/$site"
  mkdir -p "${dest%/*}"
  git clone -q "$MOCK_DATA/$site.git" "$dest"
  git -C "$dest" config user.name 'Test User'
  git -C "$dest" config user.email 'test@example.com'
  mkdir -p "$dest/.git/pantheon-local-tools"
  git config --file "$dest/.git/pantheon-local-tools/state" pantheon.site "$site"
  git config --file "$dest/.git/pantheon-local-tools/state" pantheon.environment dev
  git config --file "$dest/.git/pantheon-local-tools/state" checkout.kind canonical-dev
  git config --file "$dest/.git/pantheon-local-tools/state" local.provider "$provider"
  printf '%s\n' "$dest"
}

configure_base() {
  local provider=${1:-ddev}
  bash "$CLI" config set root "$LOCAL_ROOT"
  bash "$CLI" config set provider "$provider"
}

# Healthy setup.
scenario_init healthy
create_remote example-site 'Example Group' ddev
set_sites example-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
HEALTHY_DEST=$(create_checkout example-site clients ddev)
healthy_head=$(git -C "$HEALTHY_DEST" rev-parse HEAD)
healthy_config_hash=$(git hash-object "$PANTHEON_LOCAL_CONFIG")
healthy_output=$(bash "$CLI" doctor)
assert_contains "$healthy_output" 'Pantheon Local Tools doctor'
assert_contains "$healthy_output" 'PASS'
assert_contains "$healthy_output" 'Terminus authentication is valid'
assert_contains "$healthy_output" 'canonical Dev Git repository is readable'
assert_contains "$healthy_output" 'checkout example-site resolves provider ddev'
assert_not_contains "$healthy_output" 'FAIL'
assert_not_contains "$healthy_output" 'WARN'
healthy_json=$(bash "$CLI" doctor --format json)
assert_contains "$healthy_json" '"command":"doctor"'
assert_contains "$healthy_json" '"record_type":"diagnostic"'
assert_contains "$healthy_json" '"result":{"state":"current","reason_code":"doctor-ready","exit_code":0'
assert_contains "$healthy_json" '"id":"terminus-auth","status":"PASS"'
assert_contains "$healthy_json" '"id":"checkout-example-site-origin","status":"PASS"'
cat > "$MOCK_BIN/uname" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' Linux
MOCK
chmod +x "$MOCK_BIN/uname"
wsl_json=$(WSL_DISTRO_NAME=Ubuntu bash "$CLI" doctor --format json)
assert_contains "$wsl_json" '"platform":"wsl"'
rm -f "$MOCK_BIN/uname"
RECORD="$SCENARIO/doctor.json"
record_json=$(bash "$CLI" doctor --format json --record "$RECORD")
assert_eq "$(cat "$RECORD")" "$record_json"
set +e
bash "$CLI" doctor --record "$RECORD" >/dev/null 2>&1
record_rc=$?
set -e
assert_eq "$record_rc" '30'
assert_eq "$(git -C "$HEALTHY_DEST" rev-parse HEAD)" "$healthy_head"
assert_eq "$(git hash-object "$PANTHEON_LOCAL_CONFIG")" "$healthy_config_hash"
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'healthy doctor invoked provider'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'env:deploy'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'env:clone-content'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'multidev:create'

# Default-mode progress is line-oriented, deterministic, and separate from final stdout/JSON.
scenario_init progress
create_remote gamma-site 'Example Group' ddev
create_remote alpha-site 'Example Group' ddev
create_remote beta-site 'Example Group' ddev
set_sites gamma-site alpha-site beta-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
PROGRESS_STDOUT="$SCENARIO/default.out"
PROGRESS_STDERR="$SCENARIO/default.err"
bash "$CLI" doctor >"$PROGRESS_STDOUT" 2>"$PROGRESS_STDERR"
assert_eq "$(sed -n '1p' "$PROGRESS_STDERR")" 'Doctor: checking local prerequisites...'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: checking Terminus authentication...'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: Terminus authentication ready'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: discovering accessible Pantheon sites...'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: discovered 3 accessible sites'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: site 1/3: alpha-site — environments'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: site 1/3: alpha-site — organization'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: site 1/3: alpha-site — tags'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: site 1/3: alpha-site — routing'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: site 1/3: alpha-site — Dev Git URL'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: site 1/3: alpha-site — Git remote'
assert_file_contains "$PROGRESS_STDERR" 'Doctor: site 1/3: alpha-site — local checkout'
progress_text=$(cat "$PROGRESS_STDERR")
case "$progress_text" in
  *'Doctor: inspecting site 1/3: alpha-site'*'Doctor: inspecting site 2/3: beta-site'*'Doctor: inspecting site 3/3: gamma-site'*) ;;
  *) fail 'doctor site progress was missing or not deterministically ordered' ;;
esac
assert_file_contains "$PROGRESS_STDERR" 'Doctor: finalizing diagnostics...'
assert_file_contains "$PROGRESS_STDOUT" 'Pantheon Local Tools doctor'
assert_file_not_contains "$PROGRESS_STDOUT" 'Doctor:'
ESC=$(printf '\033')
assert_file_not_contains "$PROGRESS_STDOUT" "$ESC"
assert_file_not_contains "$PROGRESS_STDERR" "$ESC"
assert_file_not_contains "$PROGRESS_STDERR" ' complete in '

JSON_PROGRESS="$SCENARIO/json.err"
progress_json=$(bash "$CLI" doctor --format json 2>"$JSON_PROGRESS")
[ ! -s "$JSON_PROGRESS" ] || fail 'doctor JSON mode emitted progress on stderr by default'
assert_not_contains "$progress_json" 'Doctor:'
assert_contains "$progress_json" '"command":"doctor"'

PROGRESS_RECORD="$SCENARIO/doctor-record.json"
RECORD_PROGRESS="$SCENARIO/record.err"
bash "$CLI" doctor --record "$PROGRESS_RECORD" >/dev/null 2>"$RECORD_PROGRESS"
assert_file_contains "$RECORD_PROGRESS" 'Doctor: discovered 3 accessible sites'
assert_file_not_contains "$PROGRESS_RECORD" 'Doctor:'
assert_file_contains "$PROGRESS_RECORD" '"command":"doctor"'

# Optional timing mode measures external per-site reads without changing structured results.
scenario_init timing
create_remote timing-site 'Example Group' ddev
set_sites timing-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
create_checkout timing-site clients ddev >/dev/null
export MOCK_ENV_DELAY_SITE=timing-site
export MOCK_ENV_DELAY_SECONDS=2
TIMING_STDOUT="$SCENARIO/timing.out"
TIMING_STDERR="$SCENARIO/timing.err"
bash "$CLI" doctor --timing >"$TIMING_STDOUT" 2>"$TIMING_STDERR"
assert_file_contains "$TIMING_STDERR" 'Doctor: site 1/1: timing-site — environments'
assert_file_matches "$TIMING_STDERR" 'Doctor: site 1/1: timing-site — environments complete in [2-9][0-9]*s'
assert_file_not_contains "$TIMING_STDOUT" 'complete in'
TIMING_JSON_STDERR="$SCENARIO/timing-json.err"
timing_json=$(bash "$CLI" doctor --timing --format json 2>"$TIMING_JSON_STDERR")
assert_contains "$timing_json" '"command":"doctor"'
assert_not_contains "$timing_json" '"duration"'
assert_not_contains "$timing_json" '"timing"'
assert_file_matches "$TIMING_JSON_STDERR" 'Doctor: site 1/1: timing-site — environments complete in [2-9][0-9]*s'
TIMING_RECORD="$SCENARIO/timing-record.json"
TIMING_RECORD_STDERR="$SCENARIO/timing-record.err"
bash "$CLI" doctor --timing --record "$TIMING_RECORD" >/dev/null 2>"$TIMING_RECORD_STDERR"
assert_file_matches "$TIMING_RECORD_STDERR" 'Doctor: site 1/1: timing-site — environments complete in [2-9][0-9]*s'
assert_file_not_contains "$TIMING_RECORD" '"duration"'
assert_file_not_contains "$TIMING_RECORD" '"timing"'
timing_tty=$(run_doctor_pty '' --timing)
assert_contains "$timing_tty" 'environments (1s)'
unset MOCK_ENV_DELAY_SITE MOCK_ENV_DELAY_SECONDS

# Zero-site discovery still produces prompt progress and final diagnostics.
scenario_init zero-sites
: > "$MOCK_DATA/sites"
configure_base ddev
ZERO_STDERR="$SCENARIO/zero.err"
bash "$CLI" doctor >/dev/null 2>"$ZERO_STDERR"
assert_file_contains "$ZERO_STDERR" 'Doctor: discovered 0 accessible sites'
assert_file_contains "$ZERO_STDERR" 'Doctor: finalizing diagnostics...'

# Ctrl-C cancels the whole doctor process group instead of converting an interrupted child into an ordinary failure.
scenario_init interrupt
create_remote alpha-block 'Example Group' ddev
create_remote beta-later 'Example Group' ddev
set_sites alpha-block beta-later
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
export MOCK_BLOCK_ENV_SITE=alpha-block
MOCK_BLOCK_READY_FILE="$SCENARIO/block-ready"
export MOCK_BLOCK_READY_FILE
INT_STDOUT="$SCENARIO/interrupt.out"
INT_STDERR="$SCENARIO/interrupt.err"
INT_RECORD="$SCENARIO/interrupt-record.json"
set -m
bash "$CLI" doctor --record "$INT_RECORD" >"$INT_STDOUT" 2>"$INT_STDERR" &
doctor_pid=$!
set +m
ready=false
i=0
while [ "$i" -lt 50 ]; do
  if [ -f "$MOCK_BLOCK_READY_FILE" ]; then ready=true; break; fi
  sleep 0.1
  i=$((i + 1))
done
if [ "$ready" != true ]; then
  kill -TERM -- "-$doctor_pid" 2>/dev/null || true
  wait "$doctor_pid" 2>/dev/null || true
  fail 'blocking Terminus fixture did not become ready'
fi
assert_file_contains "$INT_STDERR" 'Doctor: site 1/2: alpha-block — environments'
doctor_pgid=$(ps -o pgid= -p "$doctor_pid" | tr -d ' ')
assert_eq "$doctor_pgid" "$doctor_pid"
set +e
kill -INT -- "-$doctor_pgid"
wait "$doctor_pid"
interrupt_rc=$?
set -e
assert_eq "$interrupt_rc" '130'
assert_file_contains "$INT_STDERR" 'Doctor: inspecting site 1/2: alpha-block'
assert_file_not_contains "$INT_STDERR" 'Doctor: inspecting site 2/2: beta-later'
assert_file_not_contains "$INT_STDOUT" 'Pantheon Local Tools doctor'
assert_file_contains "$MOCK_TERMINUS_LOG" 'terminus|env:list|alpha-block|--format=list|--field=id'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'terminus|env:list|beta-later|--format=list|--field=id'
[ ! -e "$INT_RECORD" ] || fail 'interrupted doctor published a partial operation record'
if find "$TMPDIR" -maxdepth 1 -type d -name 'pantheon-local-doctor.*' -print -quit | grep -q .; then
  fail 'interrupted doctor left temporary diagnostic state behind'
fi
unset MOCK_BLOCK_ENV_SITE MOCK_BLOCK_READY_FILE

# Warnings-only: missing checkout + an additional accessible unmapped Tag remain exit 0.
scenario_init warnings
create_remote warning-site $'Example Group\nInformational Tag' ddev
set_sites warning-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
warning_json=$(bash "$CLI" doctor --format json)
assert_contains "$warning_json" '"result":{"state":"complete","reason_code":"doctor-warnings","exit_code":0'
assert_contains "$warning_json" '"reason_code":"checkout-missing"'
assert_contains "$warning_json" '"remediation_class":"plt-managed","remediation_action":"checkout-create"'
assert_contains "$warning_json" '"reason_code":"accessible-tag-unmapped"'
assert_contains "$warning_json" '"remediation_class":"user-choice","remediation_action":"config-tag-route"'
assert_not_contains "$warning_json" 'Fix the'

# Narrow terminal progress must remain one physical row, including repeated frames.
scenario_init narrow-tty
long_site=example-site-with-a-deliberately-long-machine-name
create_remote "$long_site" 'Example Group' ddev
create_remote second-site 'Example Group' ddev
set_sites "$long_site" second-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
export MOCK_ENV_DELAY_SITE="$long_site"
export MOCK_ENV_DELAY_SECONDS=2
NARROW_TTY_CAPTURE="$SCENARIO/narrow-tty.output"
DOCTOR_TEST_TTY_COLS=60 run_doctor_pty $'\n' > "$NARROW_TTY_CAPTURE"
unset MOCK_ENV_DELAY_SITE MOCK_ENV_DELAY_SECONDS
python3 - "$NARROW_TTY_CAPTURE" <<'PYWIDTH'
import re
import sys
raw = open(sys.argv[1], 'rb').read().decode('utf-8', errors='replace')
plain = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', raw)
rows = [line for line in re.split(r'[\r\n]', plain) if line.startswith('Doctor: ') and '│' in line]
one = [line for line in rows if '1/2' in line]
two = [line for line in rows if '2/2' in line]
if len(one) < 2 or not two:
    raise SystemExit('FAIL: narrow TTY missed repeated first-site or second-site progress')
overflow = [line for line in rows if len(line) >= 60]
if overflow:
    raise SystemExit('FAIL: 60-column terminal overflow: %r' % overflow[0])
if not any('⠋' in line or '⠙' in line for line in one):
    raise SystemExit('FAIL: narrow TTY lost active spinner state')
# Stable status glyph columns and site field even when site names differ.
columns = [(line.index('│'), line.rindex('│')) for line in (one[0], one[-1], two[0], two[-1])]
if len(set(columns)) != 1:
    raise SystemExit('FAIL: compact site and glyph columns are not aligned: %s' % columns)
PYWIDTH

# Auto layout must remain fixed throughout a scan: live elapsed timings and
# different site-name lengths must not switch a detailed row into compact mode.
scenario_init stable-auto-layout
create_remote tiny-site 'Example Group' ddev
create_remote longer-example-site-name 'Example Group' ddev
set_sites tiny-site longer-example-site-name
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
export MOCK_ENV_DELAY_SITE=tiny-site
export MOCK_ENV_DELAY_SECONDS=2
STABLE_LAYOUT_CAPTURE="$SCENARIO/stable-layout.output"
STABLE_WIDE_CAPTURE="$SCENARIO/stable-wide.output"
DOCTOR_TEST_TTY_COLS=180 run_doctor_pty $'\n' --timing > "$STABLE_LAYOUT_CAPTURE"
DOCTOR_TEST_TTY_COLS=260 run_doctor_pty $'\n' --timing > "$STABLE_WIDE_CAPTURE"
unset MOCK_ENV_DELAY_SITE MOCK_ENV_DELAY_SECONDS
python3 - "$STABLE_LAYOUT_CAPTURE" "$STABLE_WIDE_CAPTURE" <<'PYSTABLE'
import re
import sys
raw = open(sys.argv[1], 'rb').read().decode('utf-8', errors='replace')
plain = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', raw)
rows = [row for row in re.split(r'[\r\n]', plain) if row.startswith('Doctor: ')]
full = [row for row in rows if row.startswith('Doctor: site ') and ' — ' in row]
compact = [row for row in rows if row.startswith('Doctor: ') and '│' in row]
if not full and not compact:
    raise SystemExit('FAIL: no Doctor site progress was rendered in layout-stability fixture')
if full and compact:
    raise SystemExit('FAIL: auto layout switched between full and compact during the same scan')
if not any('1/2' in row for row in full + compact):
    raise SystemExit('FAIL: first site missing in stable layout capture')
if not any('2/2' in row for row in full + compact):
    raise SystemExit('FAIL: second site missing in stable layout capture')
if not any(re.search(r'\([2-9][0-9]*s\)', row) for row in rows):
    raise SystemExit('FAIL: did not exercise growing elapsed time text')
too_wide = [row for row in full + compact if len(row) >= 180]
if too_wide:
    raise SystemExit('FAIL: progress exceeded 180-column terminal: %r' % too_wide[0])
wide_raw = open(sys.argv[2], 'rb').read().decode('utf-8', errors='replace')
wide_plain = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', wide_raw)
wide_rows = [row for row in re.split(r'[\r\n]', wide_plain) if row.startswith('Doctor: ')]
wide_full = [row for row in wide_rows if row.startswith('Doctor: site ') and ' — ' in row]
wide_compact = [row for row in wide_rows if '│' in row]
if not wide_full or wide_compact:
    raise SystemExit('FAIL: wide TTY did not stay in full layout with live timing')
if not any('1/2' in row for row in wide_full) or not any('2/2' in row for row in wide_full):
    raise SystemExit('FAIL: wide TTY failed to cover both site names')
if any(len(row) >= 260 for row in wide_full):
    raise SystemExit('FAIL: full layout exceeded 260-column terminal')
PYSTABLE

# Different layout preferences alter only interactive presentation.
scenario_init responsive-tty
create_remote example-site 'Example Group' ddev
set_sites example-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
create_checkout example-site clients ddev >/dev/null
MEDIUM_TTY_CAPTURE="$SCENARIO/medium-tty.output"
WIDE_TTY_CAPTURE="$SCENARIO/wide-tty.output"
FORCED_FULL_CAPTURE="$SCENARIO/forced-full.output"
FORCED_COMPACT_CAPTURE="$SCENARIO/forced-compact.output"
DOCTOR_TEST_TTY_COLS=115 run_doctor_pty '' > "$MEDIUM_TTY_CAPTURE"
DOCTOR_TEST_TTY_COLS=260 run_doctor_pty '' > "$WIDE_TTY_CAPTURE"
bash "$CLI" config set doctor-layout full
DOCTOR_TEST_TTY_COLS=115 run_doctor_pty '' > "$FORCED_FULL_CAPTURE"
bash "$CLI" config set doctor-layout compact
DOCTOR_TEST_TTY_COLS=260 run_doctor_pty '' > "$FORCED_COMPACT_CAPTURE"

# A route failure early in the pipeline must explain X and skipped checks.
scenario_init progress-route-failure
create_remote ambiguous-site $'Example Group\nAnother Group' ddev
set_sites ambiguous-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
bash "$CLI" config tag set 'Another Group' apps
bash "$CLI" config set doctor-layout compact
FAILURE_TTY_CAPTURE="$SCENARIO/failure-tty.output"
set +e
DOCTOR_TEST_TTY_COLS=110 run_doctor_pty $'\n' > "$FAILURE_TTY_CAPTURE"
failure_progress_rc=$?
set -e
assert_eq "$failure_progress_rc" '31'

# An absent checkout must be marked as a warning, never a passing checkout.
scenario_init progress-checkout-warning
create_remote missing-checkout-site 'Example Group' ddev
set_sites missing-checkout-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
bash "$CLI" config set doctor-layout compact
WARNING_TTY_CAPTURE="$SCENARIO/warning-tty.output"
DOCTOR_TEST_TTY_COLS=115 run_doctor_pty $'\n' > "$WARNING_TTY_CAPTURE"

python3 - "$MEDIUM_TTY_CAPTURE" "$WIDE_TTY_CAPTURE" "$FORCED_FULL_CAPTURE" "$FORCED_COMPACT_CAPTURE" "$FAILURE_TTY_CAPTURE" "$WARNING_TTY_CAPTURE" <<'PYRESPONSIVE'
import re
import sys
def read(path, width):
    raw = open(path, 'rb').read().decode('utf-8', errors='replace')
    plain = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', raw)
    progress = [line for line in re.split(r'[\r\n]', plain)
                if line.startswith('Doctor: ') and (('│' in line) or ('site ' in line and ' — ' in line))]
    if not progress:
        raise SystemExit('FAIL: missing site progress: %s' % path)
    overflow = [line for line in progress if len(line) >= width]
    if overflow:
        raise SystemExit('FAIL: overflow for %d-column TTY: %r' % (width, overflow[0]))
    return plain, progress
medium, medium_rows = read(sys.argv[1], 115)
wide, wide_rows = read(sys.argv[2], 260)
forced_full, forced_full_rows = read(sys.argv[3], 115)
forced_compact, forced_compact_rows = read(sys.argv[4], 260)
failure, failure_rows = read(sys.argv[5], 110)
warning, warning_rows = read(sys.argv[6], 115)
if '│' not in medium_rows[-1] or '✓ checked' not in medium_rows[-1]:
    raise SystemExit('FAIL: auto layout did not align/complete on medium TTY')
if not any('✓ environments' in line and '✓ organization' in line for line in wide_rows):
    raise SystemExit('FAIL: wide auto layout did not retain original step labels')
if 'Steps: ✓ environments' not in forced_full:
    raise SystemExit('FAIL: full layout lost named static summary on narrow TTY')
if '│' not in forced_compact_rows[-1] or '✓ checked' not in forced_compact_rows[-1]:
    raise SystemExit('FAIL: forced compact not honored on wide TTY')
if '× routing' not in failure_rows[-1]:
    raise SystemExit('FAIL: failed route ended on misleading checkout label')
if 'Why: site ambiguous-site matches more than one configured local Tag route' not in failure:
    raise SystemExit('FAIL: did not explain why route failed')
if 'Not checked: Dev Git URL, Git remote, local checkout (stopped after routing failed)' not in failure:
    raise SystemExit('FAIL: skipped checks lack causal explanation')
if '! local checkout' not in warning_rows[-1]:
    raise SystemExit('FAIL: absent checkout did not yield local-checkout warning')
if 'Why: canonical Dev checkout is missing for missing-checkout-site' not in warning:
    raise SystemExit('FAIL: checkout warning lacks reason')
PYRESPONSIVE

# Layout preference is presentation-only: structured diagnostics stay identical.
scenario_init layout-machine-contract
: > "$MOCK_DATA/sites"
configure_base ddev
json_auto=$(bash "$CLI" doctor --format json)
bash "$CLI" config set doctor-layout compact
json_compact=$(bash "$CLI" doctor --format json)
bash "$CLI" config set doctor-layout full
json_full=$(bash "$CLI" doctor --format json)
assert_eq "$json_auto" "$json_compact"
assert_eq "$json_auto" "$json_full"
git config --file "$PANTHEON_LOCAL_CONFIG" --replace-all local.doctor-layout invalid
set +e
invalid_layout_json=$(bash "$CLI" doctor --format json)
invalid_layout_rc=$?
set -e
assert_eq "$invalid_layout_rc" '31'
assert_contains "$invalid_layout_json" '"reason_code":"doctor-layout-invalid"'

# Interactive remediation is opt-in, previewed, delegated, and reassessed.
scenario_init remediation-decline
create_remote example-site 'Example Group' ddev
set_sites example-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
DECLINE_DEST="$LOCAL_ROOT/clients/example-site"
decline_output=$(run_doctor_pty $'\n')
assert_contains "$decline_output" 'Doctor found 1 item that needs attention.'
assert_contains "$decline_output" '1 PLT-managed item'
assert_contains "$decline_output" 'Create canonical Dev checkout for example-site'
assert_contains "$decline_output" 'Fix the 1 PLT-managed item now? [y/N]'
assert_contains "$decline_output" 'No repairs were performed.'
[ ! -e "$DECLINE_DEST" ] || fail 'doctor created a checkout without explicit remediation consent'

scenario_init remediation-accept
create_remote example-site 'Example Group' ddev
set_sites example-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
ACCEPT_DEST="$LOCAL_ROOT/clients/example-site"
accept_output=$(run_doctor_pty $'y\ny\n\n')
assert_contains "$accept_output" 'Doctor found 1 item that needs attention.'
assert_contains "$accept_output" 'PLT can fix now:'
assert_contains "$accept_output" 'Create canonical Dev checkout for example-site'
assert_contains "$accept_output" 'pantheon-local checkout example-site.dev --dry-run'
assert_contains "$accept_output" 'Create the canonical Dev checkout for example-site now? [y/N]'
assert_contains "$accept_output" 'Repairs complete.'
assert_contains "$accept_output" 'Run the full Doctor scan now? [y/N]'
assert_contains "$accept_output" 'Full estate scan skipped.'
assert_not_contains "$accept_output" 'Running Doctor again...'
[ -d "$ACCEPT_DEST/.git" ] || fail 'guided doctor remediation did not create the canonical checkout'
assert_eq "$(git config --file "$ACCEPT_DEST/.git/pantheon-local-tools/state" --get pantheon.site)" 'example-site'
assert_eq "$(git config --file "$ACCEPT_DEST/.git/pantheon-local-tools/state" --get pantheon.environment)" 'dev'
assert_eq "$(git config --file "$ACCEPT_DEST/.git/pantheon-local-tools/state" --get checkout.kind)" 'canonical-dev'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'guided checkout remediation started or invoked a provider'

# Invalid checkout root occupied by a file.
scenario_init invalid-root
create_remote root-site 'Example Group' ddev
set_sites root-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
rm -rf "$LOCAL_ROOT"
printf 'occupied\n' > "$LOCAL_ROOT"
set +e
invalid_root_json=$(bash "$CLI" doctor --format json 2>&1)
invalid_root_rc=$?
set -e
assert_eq "$invalid_root_rc" '30'
assert_contains "$invalid_root_json" '"reason_code":"root-not-directory"'

# Explicit provider missing from PATH.
scenario_init missing-provider
create_remote provider-site 'Example Group' ddev
set_sites provider-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
rm -f "$MOCK_BIN/ddev"
NO_DDEV_BIN="$SCENARIO/no-ddev-bin"
mkdir -p "$NO_DDEV_BIN"
for cmd in bash git dirname readlink mktemp rm tr sed grep sort uname awk head cat; do
  cmd_path=$(command -v "$cmd")
  ln -s "$cmd_path" "$NO_DDEV_BIN/$cmd"
done
ln -s "$MOCK_BIN/terminus" "$NO_DDEV_BIN/terminus"
PATH="$NO_DDEV_BIN"
export PATH
set +e
missing_provider_json=$(/bin/bash "$CLI" doctor --format json 2>&1)
missing_provider_rc=$?
set -e
PATH="$MOCK_BIN:$ORIGINAL_PATH"
export PATH
assert_eq "$missing_provider_rc" '40'
assert_contains "$missing_provider_json" '"reason_code":"provider-command-unavailable"'
assert_contains "$missing_provider_json" '"failure_source":"ddev"'

# Unauthenticated Terminus is authority-unavailable and does not attempt site reads.
scenario_init unauthenticated
configure_base ddev
export MOCK_AUTH_FAIL=true
UNAUTH_PROGRESS="$SCENARIO/unauth.err"
set +e
bash "$CLI" doctor >/dev/null 2>"$UNAUTH_PROGRESS"
unauth_default_rc=$?
set -e
assert_eq "$unauth_default_rc" '32'
assert_file_contains "$UNAUTH_PROGRESS" 'Doctor: checking Terminus authentication...'
assert_file_contains "$UNAUTH_PROGRESS" 'Doctor: Terminus authentication unavailable'
assert_file_contains "$UNAUTH_PROGRESS" 'Doctor: finalizing diagnostics...'
set +e
unauth_json=$(bash "$CLI" doctor --format json 2>&1)
unauth_rc=$?
set -e
unset MOCK_AUTH_FAIL
assert_eq "$unauth_rc" '32'
assert_contains "$unauth_json" '"reason_code":"terminus-unauthenticated"'
assert_contains "$unauth_json" '"failure_source":"terminus"'
assert_file_not_contains "$MOCK_TERMINUS_LOG" 'site:list'

# Unmapped and ambiguous routes fail with stable ambiguous-configuration.
scenario_init routing
create_remote unmapped-site 'Unmapped Group' ddev
create_remote ambiguous-site $'Example Group\nAnother Group' ddev
set_sites unmapped-site ambiguous-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
bash "$CLI" config tag set 'Another Group' apps
ROUTING_PROGRESS="$SCENARIO/routing.err"
set +e
bash "$CLI" doctor >/dev/null 2>"$ROUTING_PROGRESS"
routing_default_rc=$?
set -e
assert_eq "$routing_default_rc" '31'
assert_file_contains "$ROUTING_PROGRESS" 'Doctor: site 1/2: ambiguous-site — environments'
assert_file_contains "$ROUTING_PROGRESS" 'Doctor: site 1/2: ambiguous-site — organization'
assert_file_contains "$ROUTING_PROGRESS" 'Doctor: site 1/2: ambiguous-site — tags'
assert_file_contains "$ROUTING_PROGRESS" 'Doctor: site 1/2: ambiguous-site — routing'
assert_file_not_contains "$ROUTING_PROGRESS" 'Doctor: site 1/2: ambiguous-site — Dev Git URL'
set +e
routing_json=$(bash "$CLI" doctor --format json 2>&1)
routing_rc=$?
set -e
assert_eq "$routing_rc" '31'
assert_contains "$routing_json" '"reason_code":"site-route-unmapped"'
assert_contains "$routing_json" '"reason_code":"site-route-ambiguous"'
assert_contains "$routing_json" '"remediation_class":"user-choice","remediation_action":"config-tag-preference"'
assert_contains "$routing_json" '"failure_source":"plt-orchestration"'
assert_contains "$routing_json" 'Another Group -> apps'
assert_contains "$routing_json" 'Example Group -> clients'

# User-choice-only findings must still open the guided conversation.
set +e
routing_decline=$(run_doctor_pty $'
')
routing_decline_rc=$?
set -e
assert_eq "$routing_decline_rc" '31'
assert_contains "$routing_decline" '3 items needing your choice'
assert_contains "$routing_decline" 'Review the 3 items that need your attention now? [y/N]'
assert_contains "$routing_decline" 'Review skipped. No changes were made.'
assert_eq "$(bash "$CLI" config tag get 'Example Group')" 'clients'
assert_eq "$(bash "$CLI" config tag get 'Another Group')" 'apps'

set +e
routing_review=$(run_doctor_pty $'y
2
y


')
routing_review_rc=$?
set -e
assert_eq "$routing_review_rc" '31'
assert_contains "$routing_review" 'Review the 3 items that need your attention now? [y/N]'
assert_contains "$routing_review" 'Guided review'
assert_contains "$routing_review" 'Choice 1/3'
assert_contains "$routing_review" 'Which route should PLT prefer when these Tags overlap for ambiguous-site?'
assert_contains "$routing_review" 'Prefer Example Group -> clients'
assert_contains "$routing_review" 'Prefer Another Group -> apps'
assert_contains "$routing_review" 'Leave this overlap unresolved for now'
assert_contains "$routing_review" "pantheon-local config tag prefer set 'Another Group' 'Example Group'"
assert_contains "$routing_review" 'Save Another Group as the preferred route wherever these Tags overlap? [y/N]'
assert_contains "$routing_review" 'Saved route preference: Another Group'
assert_contains "$routing_review" 'Cached Tag membership: ambiguous-site now resolves via Another Group -> apps'
assert_contains "$routing_review" 'Run the full Doctor scan now? [y/N]'
assert_contains "$routing_review" 'Full estate scan skipped.'
assert_not_contains "$routing_review" 'Running Doctor again...'
assert_contains "$(bash "$CLI" config tag prefer list)" 'Another Group>Example Group'
assert_eq "$(bash "$CLI" config tag get 'Example Group')" 'clients'
assert_eq "$(bash "$CLI" config tag get 'Another Group')" 'apps'

# An initial scan can already have resolved the Tag route and inspected the
# checkout. Guided review must offer DDEV/Lando immediately for a checkout
# containing neither provider configuration; no Tag repair or rescan required.
scenario_init direct-provider-choice
create_remote direct-provider-site 'Example Group' none
set_sites direct-provider-site
configure_base lando
bash "$CLI" config tag set 'Example Group' clients
DIRECT_PROVIDER_DEST=$(create_checkout direct-provider-site clients lando)
git config --file "$DIRECT_PROVIDER_DEST/.git/pantheon-local-tools/state" --unset-all local.provider
direct_before=$(git -C "$DIRECT_PROVIDER_DEST" rev-parse HEAD)
config_before=$(git hash-object "$PANTHEON_LOCAL_CONFIG")
set +e
direct_ddev=$(run_doctor_pty $'y\n1\n\n')
direct_ddev_rc=$?
set -e
assert_eq "$direct_ddev_rc" '31'
assert_contains "$direct_ddev" 'Choice 1/1'
assert_contains "$direct_ddev" 'Which provider should direct-provider-site use?'
assert_contains "$direct_ddev" 'Preview: initialize ddev for'
assert_contains "$direct_ddev" 'Provider configuration not created.'
assert_not_contains "$direct_ddev" 'Running Doctor again...'
assert_eq "$(git hash-object "$PANTHEON_LOCAL_CONFIG")" "$config_before"
assert_eq "$(git -C "$DIRECT_PROVIDER_DEST" rev-parse HEAD)" "$direct_before"
[ ! -e "$DIRECT_PROVIDER_DEST/.ddev/config.yaml" ] || fail 'direct DDEV choice created provider configuration'
[ ! -e "$DIRECT_PROVIDER_DEST/.lando.yml" ] || fail 'direct DDEV choice created Lando configuration'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'direct DDEV choice started a provider'
set +e
direct_lando=$(run_doctor_pty $'y\n2\n\n')
direct_lando_rc=$?
set -e
assert_eq "$direct_lando_rc" '31'
assert_contains "$direct_lando" 'Preview: initialize lando for'
assert_contains "$direct_lando" 'Provider configuration not created.'
set +e
direct_skip=$(run_doctor_pty $'y\n\n')
direct_skip_rc=$?
set -e
assert_eq "$direct_skip_rc" '31'
assert_contains "$direct_skip" 'Provider remains unresolved. No files or settings were changed.'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'direct provider choice invoked DDEV/Lando'
assert_eq "$(git hash-object "$PANTHEON_LOCAL_CONFIG")" "$config_before"

# A new provider configuration is created only after a separate Yes.
scenario_init direct-ddev-initialization
create_remote init-ddev-site 'Example Group' none
set_sites init-ddev-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
INIT_DDEV_DEST=$(create_checkout init-ddev-site clients ddev)
git config --file "$INIT_DDEV_DEST/.git/pantheon-local-tools/state" --unset-all local.provider
export MOCK_DDEV_CONFIG_ENABLED=true
set +e
init_ddev_output=$(run_doctor_pty $'y\n1\ny\n')
init_ddev_rc=$?
set -e
unset MOCK_DDEV_CONFIG_ENABLED
assert_eq "$init_ddev_rc" '31'
assert_contains "$init_ddev_output" 'Preview: initialize ddev for init-ddev-site'
assert_contains "$init_ddev_output" 'Create ddev project configuration for init-ddev-site now? [y/N]'
assert_contains "$init_ddev_output" 'Verified ddev provider configuration (not started)'
[ -f "$INIT_DDEV_DEST/.ddev/config.yaml" ] || fail 'consented DDEV project config missing'
[ -f "$INIT_DDEV_DEST/.ddev/providers/pantheon.yaml" ] || fail 'consented DDEV Pantheon provider missing'
[ ! -s "$MOCK_PROVIDER_LOG" ] && fail 'consented DDEV config command was not invoked'
grep -F ' config ' "$MOCK_PROVIDER_LOG" >/dev/null || fail 'expected ddev config generation'
if grep -E '(start|pull|rebuild|composer|drush)' "$MOCK_PROVIDER_LOG" >/dev/null; then fail 'Doctor unexpectedly started provider/data workflow'; fi

scenario_init direct-lando-initialization
create_remote init-lando-site 'Example Group' none
set_sites init-lando-site
configure_base lando
bash "$CLI" config tag set 'Example Group' clients
INIT_LANDO_DEST=$(create_checkout init-lando-site clients lando)
git config --file "$INIT_LANDO_DEST/.git/pantheon-local-tools/state" --unset-all local.provider
set +e
init_lando_output=$(run_doctor_pty $'y\n2\ny\n')
init_lando_rc=$?
set -e
assert_eq "$init_lando_rc" '31'
assert_contains "$init_lando_output" 'Preview: initialize lando for init-lando-site'
assert_contains "$init_lando_output" 'Create lando project configuration for init-lando-site now? [y/N]'
assert_contains "$init_lando_output" 'Verified lando provider configuration (not started)'
[ -f "$INIT_LANDO_DEST/.lando.yml" ] || fail 'consented Pantheon Lando recipe missing'
grep -Fx 'recipe: pantheon' "$INIT_LANDO_DEST/.lando.yml" >/dev/null || fail 'Lando recipe incorrect'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'Lando init ran provider runtime'
assert_file_contains "$MOCK_TERMINUS_LOG" 'terminus|site:info|init-lando-site|--field=id'

# After a confirmed route preference, continue read-only diagnostics for the
# same site (Dev Git + checkout/provider), without a 34-site/full-estate rescan.
scenario_init same-site-continuation
create_remote example-route-site $'General Group\nSpecific Group' ddev
set_sites example-route-site
configure_base ddev
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
SAME_SITE_DEST=$(create_checkout example-route-site specific ddev)
set +e
same_site_output=$(run_doctor_pty $'y\n2\ny\n\n')
same_site_rc=$?
set -e
assert_eq "$same_site_rc" '31'
assert_contains "$same_site_output" 'Saved route preference: Specific Group'
assert_contains "$same_site_output" 'Continuing checks for example-route-site'
assert_contains "$same_site_output" 'Dev Git: reachable for this site'
assert_contains "$same_site_output" 'Provider: ddev'
assert_contains "$same_site_output" 'Local checkout: checked'
assert_contains "$same_site_output" 'Full estate scan skipped.'
assert_not_contains "$same_site_output" 'Running Doctor again...'
assert_file_contains "$MOCK_TERMINUS_LOG" 'terminus|connection:info|example-route-site.dev|--field=git_url'
[ -d "$SAME_SITE_DEST/.git" ] || fail 'same-site continuation changed the checkout'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'same-site continuation started a provider'

# When checkout is missing, offer its owning command without creating it by
# default or silently starting a provider, then explain what is still needed.
scenario_init same-site-missing-checkout
create_remote missing-route-site $'General Group\nSpecific Group' ddev
set_sites missing-route-site
configure_base ddev
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
set +e
missing_site_output=$(run_doctor_pty $'y\n2\ny\n\n\n')
missing_site_rc=$?
set -e
assert_eq "$missing_site_rc" '31'
assert_contains "$missing_site_output" 'Continuing checks for missing-route-site'
assert_contains "$missing_site_output" 'Why: canonical Dev checkout is missing for missing-route-site'
assert_contains "$missing_site_output" 'pantheon-local checkout missing-route-site.dev --dry-run'
assert_contains "$missing_site_output" 'Create the canonical Dev checkout for missing-route-site now? [y/N]'
assert_contains "$missing_site_output" 'Checkout not created.'
assert_contains "$missing_site_output" 'Full estate scan skipped.'
[ ! -e "$LOCAL_ROOT/specific/missing-route-site" ] || fail 'missing checkout was created without consent'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'missing checkout preview started a provider'

# Explicit checkout consent completes the same site's checkout/provider
# inspection. The owning checkout command may clone, but Doctor never starts
# DDEV, Lando, Composer or Docker.
scenario_init same-site-checkout-accept
create_remote create-route-site $'General Group\nSpecific Group' ddev
set_sites create-route-site
configure_base ddev
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
set +e
created_site_output=$(run_doctor_pty $'y\n2\ny\ny\n\n')
created_site_rc=$?
set -e
assert_eq "$created_site_rc" '31'
assert_contains "$created_site_output" 'Continuing checks for create-route-site'
assert_contains "$created_site_output" 'Create the canonical Dev checkout for create-route-site now? [y/N]'
assert_contains "$created_site_output" 'Verifying checkout for create-route-site'
assert_contains "$created_site_output" 'Provider: ddev (detected, not started)'
[ -d "$LOCAL_ROOT/specific/create-route-site/.git" ] || fail 'authorized checkout was not created'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'checkout follow-up started a provider'

# When the project has neither provider configuration, Doctor remains on that
# site and explains the missing decision rather than changing a global setting.
scenario_init same-site-provider-unresolved
create_remote no-provider-site $'General Group\nSpecific Group' none
set_sites no-provider-site
configure_base auto
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
NO_PROVIDER_DEST=$(create_checkout no-provider-site specific ddev)
git config --file "$NO_PROVIDER_DEST/.git/pantheon-local-tools/state" --unset-all local.provider
set +e
no_provider_output=$(run_doctor_pty $'y\n2\ny\n2\n\n\n')
no_provider_rc=$?
set -e
assert_eq "$no_provider_rc" '31'
assert_contains "$no_provider_output" 'Continuing checks for no-provider-site'
assert_contains "$no_provider_output" 'Why: checkout no-provider-site contains neither DDEV nor Lando project configuration'
assert_contains "$no_provider_output" 'Provider: unresolved (review DDEV/Lando project configuration)'
assert_contains "$no_provider_output" 'Which provider should no-provider-site use?'
assert_contains "$no_provider_output" 'DDEV — initialize the missing project configuration'
assert_contains "$no_provider_output" 'Lando — initialize the missing Pantheon project recipe'
assert_contains "$no_provider_output" 'Preview: initialize lando for'
assert_contains "$no_provider_output" 'Provider configuration not created.'
assert_contains "$no_provider_output" 'No provider or Docker runtime was started by Doctor.'
[ ! -e "$NO_PROVIDER_DEST/.lando.yml" ] || fail 'provider choice generated Lando config'
[ ! -e "$NO_PROVIDER_DEST/.ddev/config.yaml" ] || fail 'provider choice generated DDEV config'
[ -z "$(git config --file "$NO_PROVIDER_DEST/.git/pantheon-local-tools/state" --get local.provider 2>/dev/null || true)" ] || fail 'provider guidance unexpectedly wrote checkout metadata'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'provider ambiguity started a provider'

# Explicit DDEV choice remains local guidance, never silent project setup.
scenario_init same-site-provider-ddev-choice
create_remote choose-ddev-site $'General Group\nSpecific Group' none
set_sites choose-ddev-site
configure_base auto
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
CHOOSE_DDEV_DEST=$(create_checkout choose-ddev-site specific ddev)
git config --file "$CHOOSE_DDEV_DEST/.git/pantheon-local-tools/state" --unset-all local.provider
set +e
choose_ddev_output=$(run_doctor_pty $'y\n2\ny\n1\n\n\n')
choose_ddev_rc=$?
set -e
assert_eq "$choose_ddev_rc" '31'
assert_contains "$choose_ddev_output" 'Preview: initialize ddev for'
assert_contains "$choose_ddev_output" 'Provider configuration not created.'
[ ! -e "$CHOOSE_DDEV_DEST/.ddev/config.yaml" ] || fail 'DDEV guidance created project configuration'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'DDEV guidance started provider'

# The default provider answer leaves unsafe/ambiguous state unchanged.
scenario_init same-site-provider-decline
create_remote leave-provider-site $'General Group\nSpecific Group' none
set_sites leave-provider-site
configure_base auto
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
LEAVE_PROVIDER_DEST=$(create_checkout leave-provider-site specific ddev)
git config --file "$LEAVE_PROVIDER_DEST/.git/pantheon-local-tools/state" --unset-all local.provider
set +e
leave_provider_output=$(run_doctor_pty $'y\n2\ny\n\n\n')
leave_provider_rc=$?
set -e
assert_eq "$leave_provider_rc" '31'
assert_contains "$leave_provider_output" 'Which provider should leave-provider-site use?'
assert_contains "$leave_provider_output" 'Provider remains unresolved. No files or settings were changed.'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'declined provider choice started provider'

# A missing checkout followed by its explicit creation must ask DDEV/Lando
# if the cloned project contains neither provider configuration.
scenario_init missing-project-provider-after-checkout
create_remote example-provider-site $'General Group\nSpecific Group' none
set_sites example-provider-site
configure_base auto
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
set +e
result=$(run_doctor_pty $'y\n2\ny\ny\n1\n\n\n')
rc=$?
set -e
assert_eq "$rc" '31'
assert_contains "$result" 'Continuing checks for example-provider-site'
assert_contains "$result" 'Create the canonical Dev checkout for example-provider-site now? [y/N]'
assert_contains "$result" 'Verifying checkout for example-provider-site'
assert_contains "$result" 'Which provider should example-provider-site use?'
assert_contains "$result" 'Preview: initialize ddev for'
assert_contains "$result" 'Full estate scan skipped.'
[ -d "$LOCAL_ROOT/specific/example-provider-site/.git" ] || fail 'authorized canonical checkout was not created'
[ ! -e "$LOCAL_ROOT/specific/example-provider-site/.ddev/config.yaml" ] || fail 'DDEV config was synthesized'
[ ! -e "$LOCAL_ROOT/specific/example-provider-site/.lando.yml" ] || fail 'Lando config was synthesized'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'Doctor started a provider'
# Per-site continuation fails closed on Git connection authority without
# creating checkouts or silently probing any other site after the route fix.
scenario_init same-site-git-url-unavailable
create_remote blocked-route-site $'General Group\nSpecific Group' ddev
set_sites blocked-route-site
configure_base ddev
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
export MOCK_CONNECTION_FAIL_SITE=blocked-route-site
set +e
blocked_site_output=$(run_doctor_pty $'y\n2\ny\n\n')
blocked_site_rc=$?
set -e
assert_eq "$blocked_site_rc" '31'
assert_contains "$blocked_site_output" 'Continuing checks for blocked-route-site'
assert_contains "$blocked_site_output" 'Why: canonical Dev Git URL is unavailable for blocked-route-site'
assert_not_contains "$blocked_site_output" 'Create the canonical Dev checkout for blocked-route-site now?'
[ ! -e "$LOCAL_ROOT/specific/blocked-route-site" ] || fail 'unavailable authority created a checkout'
unset MOCK_CONNECTION_FAIL_SITE

# A strict-subset Tag cohort is recommended as the more-specific route, but still requires explicit choice and confirmation.
scenario_init route-specificity
create_remote general-site 'General Group' ddev
create_remote specific-site $'General Group\nSpecific Group' ddev
set_sites general-site specific-site
configure_base ddev
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
GENERAL_DEST=$(create_checkout general-site general ddev)
SPECIFIC_DEST=$(create_checkout specific-site specific ddev)

set +e
specificity_review=$(run_doctor_pty $'y\n2\ny\n\n')
specificity_review_rc=$?
set -e
assert_eq "$specificity_review_rc" '31'
assert_contains "$specificity_review" 'Review the 1 item that needs your attention now? [y/N]'
assert_contains "$specificity_review" 'Suggested: Specific Group (most-specific observed Tag cohort)'
assert_contains "$specificity_review" 'Prefer General Group -> general (2 observed sites)'
assert_contains "$specificity_review" 'Prefer Specific Group -> specific (1 observed sites) — recommended: most specific observed cohort'
assert_contains "$specificity_review" "pantheon-local config tag prefer set 'Specific Group' 'General Group'"
assert_contains "$specificity_review" 'Save Specific Group as the preferred route wherever these Tags overlap? [y/N]'
assert_contains "$specificity_review" 'Saved route preference: Specific Group'
assert_contains "$specificity_review" 'Cached Tag membership: specific-site now resolves via Specific Group -> specific'
assert_contains "$specificity_review" 'Full estate scan skipped.'
assert_not_contains "$specificity_review" 'Running Doctor again...'
assert_contains "$(bash "$CLI" config tag prefer list)" 'Specific Group>General Group'
[ -d "$GENERAL_DEST/.git" ] || fail 'general checkout disappeared during route preference review'
[ -d "$SPECIFIC_DEST/.git" ] || fail 'specific checkout disappeared during route preference review'

# An explicit Yes at the rescan boundary still performs fresh diagnostics.
bash "$CLI" config tag prefer unset 'Specific Group' 'General Group'
set +e
rescan_accept=$(run_doctor_pty $'y\n2\ny\ny\n')
rescan_accept_rc=$?
set -e
assert_eq "$rescan_accept_rc" '0'
assert_contains "$rescan_accept" 'Run the full Doctor scan now? [y/N]'
assert_contains "$rescan_accept" 'Running Doctor again...'
assert_contains "$rescan_accept" 'Doctor: all checks passed.'

# One saved pairwise preference can resolve many originally ambiguous sites
# from the same observed estate without prompting again or rescanning the estate.
scenario_init repeated-overlap
create_remote general-only 'General Group' ddev
create_remote shared-one $'General Group\nSpecific Group' ddev
create_remote shared-two $'General Group\nSpecific Group' ddev
set_sites general-only shared-one shared-two
configure_base ddev
bash "$CLI" config tag set 'General Group' general
bash "$CLI" config tag set 'Specific Group' specific
create_checkout general-only general ddev >/dev/null
create_checkout shared-one specific ddev >/dev/null
create_checkout shared-two specific ddev >/dev/null
set +e
overlap_output=$(run_doctor_pty $'y\n2\ny\n\n')
overlap_rc=$?
set -e
assert_eq "$overlap_rc" '31'
assert_contains "$overlap_output" 'Saved route preference: Specific Group'
assert_contains "$overlap_output" 'Already resolved from this run'
assert_contains "$overlap_output" 'shared-two -> Specific Group -> specific'
assert_eq "$(bash "$CLI" config tag prefer list)" 'Specific Group>General Group'
choose_count=$(printf '%s\n' "$overlap_output" | grep -F -c 'Which route should PLT prefer when these Tags overlap' || true)
assert_eq "$choose_count" '1'
rescan_count=$(printf '%s\n' "$overlap_output" | grep -F -c 'Run the full Doctor scan now?' || true)
assert_eq "$rescan_count" '1'
assert_contains "$overlap_output" 'Full estate scan skipped.'
assert_not_contains "$overlap_output" 'Running Doctor again...'

# A failing SSH host-key check is classified without trusting any new host.
scenario_init ssh-host-key
create_remote key-site 'Example Group' ddev
set_sites key-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
export MOCK_SSH_GIT_SITE=key-site
MOCK_SSH_LOG="$SCENARIO/ssh-args.log"
export MOCK_SSH_LOG
cat > "$MOCK_BIN/ssh" <<'SSHMOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_SSH_LOG:?}"
printf '%s\n' 'Host key verification failed.' >&2
exit 255
SSHMOCK
chmod +x "$MOCK_BIN/ssh"
set +e
ssh_host_json=$(bash "$CLI" doctor --format json)
ssh_host_rc=$?
set -e
assert_eq "$ssh_host_rc" '32'
assert_contains "$ssh_host_json" '"reason_code":"git-ssh-host-key-untrusted"'
assert_contains "$ssh_host_json" 'verify the SSH host fingerprint'
assert_file_contains "$MOCK_SSH_LOG" 'StrictHostKeyChecking=yes'
assert_file_contains "$MOCK_SSH_LOG" 'ConnectTimeout=20'
[ ! -e "$HOME/.ssh/known_hosts" ] || fail 'Doctor silently accepted an untrusted SSH host key'
unset MOCK_SSH_GIT_SITE MOCK_SSH_LOG

# Provider auto-detection ambiguity is reported from the checkout itself.
scenario_init provider-ambiguity
create_remote auto-site 'Example Group' ddev
set_sites auto-site
configure_base auto
bash "$CLI" config tag set 'Example Group' clients
AUTO_DEST=$(create_checkout auto-site clients ddev)
git config --file "$AUTO_DEST/.git/pantheon-local-tools/state" --unset-all local.provider
printf 'name: auto-site\nrecipe: pantheon\n' > "$AUTO_DEST/.lando.yml"
set +e
provider_amb_json=$(bash "$CLI" doctor --format json 2>&1)
provider_amb_rc=$?
set -e
assert_eq "$provider_amb_rc" '31'
assert_contains "$provider_amb_json" '"reason_code":"provider-auto-ambiguous"'

# A checkout on an old local branch is a manual-recovery finding; Doctor
# never switches branches, resets HEAD, or touches local project files.
scenario_init checkout-branch-manual
create_remote legacy-branch-site 'Example Group' ddev
set_sites legacy-branch-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
LEGACY_BRANCH_DEST=$(create_checkout legacy-branch-site clients ddev)
git -C "$LEGACY_BRANCH_DEST" branch -m legacy-main
legacy_branch_head=$(git -C "$LEGACY_BRANCH_DEST" rev-parse HEAD)
legacy_branch_status=$(git -C "$LEGACY_BRANCH_DEST" status --porcelain)
legacy_config_hash=$(git hash-object "$PANTHEON_LOCAL_CONFIG")

set +e
legacy_branch_json=$(bash "$CLI" doctor --format json)
legacy_branch_json_rc=$?
set -e
assert_eq "$legacy_branch_json_rc" '30'
assert_contains "$legacy_branch_json" '"reason_code":"checkout-branch-mismatch"'
assert_contains "$legacy_branch_json" '"remediation_class":"manual-recovery"'

set +e
legacy_branch_review=$(run_doctor_pty $'y\n1\n\n')
legacy_branch_review_rc=$?
set -e
assert_eq "$legacy_branch_review_rc" '30'
assert_contains "$legacy_branch_review" 'Manual recovery 1/1'
assert_contains "$legacy_branch_review" 'Show manual/external recovery guidance for 1 finding now? [y/N]'
assert_contains "$legacy_branch_review" 'No automatic fixes or configurable choices exist for these findings.'
assert_contains "$legacy_branch_review" 'What would you like to inspect?'
assert_contains "$legacy_branch_review" 'Read-only branch mismatch inspection'
assert_contains "$legacy_branch_review" 'Doctor will not switch branches, reset HEAD, or discard work.'
assert_contains "$legacy_branch_review" 'checkout branch is legacy-main, canonical Dev branch is master'
assert_contains "$legacy_branch_review" 'Guided review complete. No unconfirmed changes were made.'
assert_eq "$(git -C "$LEGACY_BRANCH_DEST" symbolic-ref --short HEAD)" 'legacy-main'
assert_eq "$(git -C "$LEGACY_BRANCH_DEST" rev-parse HEAD)" "$legacy_branch_head"
assert_eq "$(git -C "$LEGACY_BRANCH_DEST" status --porcelain)" "$legacy_branch_status"
assert_eq "$(git hash-object "$PANTHEON_LOCAL_CONFIG")" "$legacy_config_hash"
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'Doctor tried a provider operation while reviewing a branch mismatch'

# The default Finish option must leave the old checkout branch untouched.
set +e
legacy_finish=$(run_doctor_pty $'y\n\n')
legacy_finish_rc=$?
set -e
assert_eq "$legacy_finish_rc" '30'
assert_contains "$legacy_finish" 'Finish review (default; no changes)'
assert_contains "$legacy_finish" 'Guided review complete. No unconfirmed changes were made.'
assert_not_contains "$legacy_finish" 'Read-only branch mismatch inspection'
assert_eq "$(git -C "$LEGACY_BRANCH_DEST" symbolic-ref --short HEAD)" 'legacy-main'
assert_eq "$(git -C "$LEGACY_BRANCH_DEST" rev-parse HEAD)" "$legacy_branch_head"

# An estate with both manual and external findings offers a small, default-safe
# category menu instead of 11 identical yes/no prompts or any automatic fix.
scenario_init branch-and-ssh-guidance
create_remote legacy-site 'Example Group' ddev
create_remote ssh-key-site 'Example Group' ddev
set_sites legacy-site ssh-key-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
MIXED_BRANCH_DEST=$(create_checkout legacy-site clients ddev)
git -C "$MIXED_BRANCH_DEST" branch -m old-master
mixed_branch_head=$(git -C "$MIXED_BRANCH_DEST" rev-parse HEAD)
mixed_branch_status=$(git -C "$MIXED_BRANCH_DEST" status --porcelain)
mixed_config_hash=$(git hash-object "$PANTHEON_LOCAL_CONFIG")
export MOCK_SSH_GIT_SITE=ssh-key-site
cat > "$MOCK_BIN/ssh" <<'SSH_MIXED_MOCK'
#!/usr/bin/env bash
printf '%s\\n' 'Host key verification failed.' >&2
exit 255
SSH_MIXED_MOCK
chmod +x "$MOCK_BIN/ssh"

set +e
mixed_review=$(run_doctor_pty $'y\n1\n2\n\n')
mixed_review_rc=$?
set -e
assert_eq "$mixed_review_rc" '32'
assert_contains "$mixed_review" 'Show manual/external recovery guidance for 2 findings now? [y/N]'
assert_contains "$mixed_review" 'Inspect 1 checkout branch mismatch (no branch changes)'
assert_contains "$mixed_review" 'Review 1 SSH host-key finding (no trust changes)'
assert_contains "$mixed_review" 'Read-only branch mismatch inspection'
assert_contains "$mixed_review" 'Read-only SSH host-key inspection'
assert_contains "$mixed_review" 'Never disable host-key verification or blindly import scanned keys.'
assert_contains "$mixed_review" 'Finish review (default; no changes)'
assert_contains "$mixed_review" 'Guided review complete. No unconfirmed changes were made.'
assert_eq "$(git -C "$MIXED_BRANCH_DEST" symbolic-ref --short HEAD)" 'old-master'
assert_eq "$(git -C "$MIXED_BRANCH_DEST" rev-parse HEAD)" "$mixed_branch_head"
assert_eq "$(git -C "$MIXED_BRANCH_DEST" status --porcelain)" "$mixed_branch_status"
assert_eq "$(git hash-object "$PANTHEON_LOCAL_CONFIG")" "$mixed_config_hash"
[ ! -e "$HOME/.ssh/known_hosts" ] || fail 'manual/external review added SSH trust'
[ ! -s "$MOCK_PROVIDER_LOG" ] || fail 'manual/external review started provider'
unset MOCK_SSH_GIT_SITE

# Checkout-local metadata inconsistency is unsafe local state.
scenario_init metadata
create_remote metadata-site 'Example Group' ddev
set_sites metadata-site
configure_base ddev
bash "$CLI" config tag set 'Example Group' clients
META_DEST=$(create_checkout metadata-site clients ddev)
git config --file "$META_DEST/.git/pantheon-local-tools/state" pantheon.site wrong-site
set +e
metadata_json=$(bash "$CLI" doctor --format json 2>&1)
metadata_rc=$?
set -e
assert_eq "$metadata_rc" '30'
assert_contains "$metadata_json" '"reason_code":"checkout-site-mismatch"'
assert_contains "$metadata_json" '"failure_source":"git"'

# Missing Git: doctor still returns structured diagnostics instead of crashing.
scenario_init missing-git
configure_base ddev
NOGIT_BIN="$SCENARIO/nogit-bin"
mkdir -p "$NOGIT_BIN"
for cmd in bash dirname readlink mktemp rm tr sed grep sort uname; do
  cmd_path=$(command -v "$cmd")
  ln -s "$cmd_path" "$NOGIT_BIN/$cmd"
done
ln -s "$MOCK_BIN/terminus" "$NOGIT_BIN/terminus"
PATH="$NOGIT_BIN"
export PATH
set +e
missing_git_json=$(/bin/bash "$CLI" doctor --format json 2>&1)
missing_git_rc=$?
set -e
PATH="$MOCK_BIN:$ORIGINAL_PATH"
export PATH
assert_eq "$missing_git_rc" '40'
assert_contains "$missing_git_json" '"reason_code":"git-unavailable"'
assert_contains "$missing_git_json" '"reason_code":"config-unreadable-without-git"'

# Legacy format spelling is rejected.
scenario_init format
configure_base ddev
set +e
bash "$CLI" doctor --format human >/dev/null 2>&1
legacy_rc=$?
set -e
assert_eq "$legacy_rc" '64'

printf 'doctor tests passed\n'
