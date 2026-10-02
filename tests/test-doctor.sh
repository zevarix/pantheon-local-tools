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
  unset MOCK_AUTH_FAIL MOCK_SITE_LIST_FAIL MOCK_ENV_FAIL_SITE MOCK_TAG_FAIL_SITE MOCK_CONNECTION_FAIL_SITE MOCK_BLOCK_ENV_SITE MOCK_BLOCK_READY_FILE
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
    [ "${3:-}" = '--field=organization' ] || exit 2
    printf '%s\n' 'Example Org'
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
    cat "${MOCK_DATA:?}/$site.git-url"
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
progress_text=$(cat "$PROGRESS_STDERR")
case "$progress_text" in
  *'Doctor: inspecting site 1/3: alpha-site'*'Doctor: inspecting site 2/3: beta-site'*'Doctor: inspecting site 3/3: gamma-site'*) ;;
  *) fail 'doctor site progress was missing or not deterministically ordered' ;;
esac
assert_file_contains "$PROGRESS_STDERR" 'Doctor: finalizing diagnostics...'
assert_file_contains "$PROGRESS_STDOUT" 'Pantheon Local Tools doctor'
assert_file_not_contains "$PROGRESS_STDOUT" 'Doctor:'

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
assert_contains "$warning_json" '"reason_code":"accessible-tag-unmapped"'

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
set +e
routing_json=$(bash "$CLI" doctor --format json 2>&1)
routing_rc=$?
set -e
assert_eq "$routing_rc" '31'
assert_contains "$routing_json" '"reason_code":"site-route-unmapped"'
assert_contains "$routing_json" '"reason_code":"site-route-ambiguous"'
assert_contains "$routing_json" '"failure_source":"plt-orchestration"'

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
