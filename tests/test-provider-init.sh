#!/usr/bin/env bash
set -euo pipefail
REPO=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
CLI="$REPO/bin/pantheon-local"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin"
export HOME="$TMP/home" PANTHEON_LOCAL_CONFIG="$TMP/config/plt"
export MOCK_LOG="$TMP/provider.log" MOCK_TERMINUS_LOG="$TMP/terminus.log"
: > "$MOCK_LOG"; : > "$MOCK_TERMINUS_LOG"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { case "$1" in *"$2"*) ;; *) fail "missing [$2]" ;; esac; }
cat > "$TMP/bin/ddev" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'ddev|%s\n' "$*" >> "$MOCK_LOG"
# Each provider creation must use temporary DDEV global settings, never HOME.
case "${DDEV_XDG_CONFIG_HOME:-}" in
  */.plt-provider-init.*/ddev-global) ;;
  *) printf 'DDEV global registry was not isolated\n' >&2; exit 93 ;;
esac
[ "${1:-}" = config ] || exit 91
[ "${MOCK_DDEV_FAIL:-false}" != true ] || exit 9
mkdir -p .ddev/providers
printf 'name: example-site\ntype: drupal11\ndocroot: web\n' > .ddev/config.yaml
printf '# Pantheon fixture\n' > .ddev/providers/pantheon.yaml
MOCK
cat > "$TMP/bin/lando" <<'MOCK'
#!/usr/bin/env bash
printf 'lando|%s\n' "$*" >> "$MOCK_LOG"
exit 91
MOCK
cat > "$TMP/bin/terminus" <<'MOCK'
#!/usr/bin/env bash
printf 'terminus|%s\n' "$*" >> "$MOCK_TERMINUS_LOG"
[ "${1:-}" = site:info ] && [ "${2:-}" = example-site ] || exit 9
case "${3:-}" in
  --field=id) printf '%s\n' "${MOCK_SITE_ID:-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}" ;;
  --field=framework) printf '%s\n' drupal8 ;;
  *) exit 9 ;;
esac
MOCK
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
fixture() {
  local folder=$1
  mkdir -p "$folder/web"
  git -C "$folder" init -q
  git -C "$folder" config user.name 'Test Author'
  git -C "$folder" config user.email 'author@example.com'
  printf '<?php\n' > "$folder/web/index.php"
  printf '%s\n' '{"require":{"drupal/core-recommended":"^11.4"}}' > "$folder/composer.json"
  git -C "$folder" add .; git -C "$folder" commit -qm Fixture
  mkdir -p "$folder/.git/pantheon-local-tools"
  git config --file "$folder/.git/pantheon-local-tools/state" pantheon.site example-site
  git config --file "$folder/.git/pantheon-local-tools/state" pantheon.environment dev
  git config --file "$folder/.git/pantheon-local-tools/state" checkout.kind canonical-dev
}
for case in ddev lando collision fail bad-id; do fixture "$TMP/$case"; done
contains "$(bash "$CLI" --help)" 'pantheon-local provider init --provider ddev|lando'
preview=$(cd "$TMP/ddev" && bash "$CLI" provider init --provider ddev --dry-run)
contains "$preview" 'ddev config --auto --project-type=drupal11 --docroot=web --project-name=example-site'
[ ! -e "$TMP/ddev/.ddev" ] || fail 'dry-run created DDEV config'
[ ! -s "$MOCK_LOG" ] || fail 'dry-run called DDEV'
output=$(cd "$TMP/ddev" && bash "$CLI" provider init --provider ddev)
contains "$output" 'Created ddev project configuration (not started).'
if [ ! -f "$TMP/ddev/.ddev/config.yaml" ] || [ ! -f "$TMP/ddev/.ddev/providers/pantheon.yaml" ]; then
  fail 'DDEV generated incomplete config'
fi
grep -F 'ddev|config --auto --project-type=drupal11 --docroot=web --project-name=example-site' "$MOCK_LOG" >/dev/null || fail 'DDEV command incorrect'
if find "$TMP/ddev" -maxdepth 1 -name '.plt-provider-init.*' -print -quit | grep -q .; then fail 'successful DDEV config retained staging/global registry'; fi
if (cd "$TMP/ddev" && bash "$CLI" provider init --provider ddev) >/dev/null 2>&1; then fail 'DDEV overwrite permitted'; fi
preview=$(cd "$TMP/lando" && bash "$CLI" provider init --provider lando --dry-run)
contains "$preview" 'framework: drupal8'
contains "$preview" 'id: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
contains "$preview" 'a later lando start may run Composer install when Pantheon build_step is enabled.'
contains "$preview" 'Inspect composer.json and composer.lock changes after starting Lando.'
[ ! -e "$TMP/lando/.lando.yml" ] || fail 'Lando dry-run created file'
output=$(cd "$TMP/lando" && bash "$CLI" provider init --provider lando)
contains "$output" 'Created lando project configuration (not started).'
contains "$output" 'a later lando start may run Composer install when Pantheon build_step is enabled.'
grep -Fx 'recipe: pantheon' "$TMP/lando/.lando.yml" >/dev/null || fail 'recipe not Pantheon'
grep -Fx '  site: example-site' "$TMP/lando/.lando.yml" >/dev/null || fail 'Pantheon identity absent'
if (cd "$TMP/lando" && bash "$CLI" provider init --provider ddev) >/dev/null 2>&1; then fail 'provider switch allowed'; fi
printf 'name: existing\n' > "$TMP/collision/.lando.local.yml"
if (cd "$TMP/collision" && bash "$CLI" provider init --provider ddev) >/dev/null 2>&1; then fail 'existing override ignored'; fi
git config --file "$TMP/collision/.git/pantheon-local-tools/state" local.provider lando
if (cd "$TMP/collision" && bash "$CLI" provider init --provider ddev) >/dev/null 2>&1; then fail 'recorded provider conflict allowed'; fi
export MOCK_DDEV_FAIL=true
if (cd "$TMP/fail" && bash "$CLI" provider init --provider ddev) >/dev/null 2>&1; then fail 'failed DDEV generation reported success'; fi
[ ! -e "$TMP/fail/.ddev" ] || fail 'partial DDEV config installed'
if find "$TMP/fail" -maxdepth 1 -name '.plt-provider-init.*' | grep -q .; then fail 'staging not removed'; fi
unset MOCK_DDEV_FAIL
export MOCK_SITE_ID=bad-id
if (cd "$TMP/bad-id" && bash "$CLI" provider init --provider lando) >/dev/null 2>&1; then fail 'invalid site ID accepted'; fi
[ ! -e "$TMP/bad-id/.lando.yml" ] || fail 'invalid identity wrote file'
unset MOCK_SITE_ID
if grep -E 'ddev[|](start|rebuild)|lando[|](start|rebuild)' "$MOCK_LOG" >/dev/null; then fail 'provider runtime started'; fi
printf 'provider init tests passed\n'
