#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools landing-page validator'

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
HTML_FILE=${1:-"$REPO_ROOT/packaging/debian/apt-index.html"}
CSS_FILE=${2:-"$REPO_ROOT/packaging/debian/apt-index.css"}

[ -s "$HTML_FILE" ] || die "HTML source is missing or empty: $HTML_FILE"
[ -s "$CSS_FILE" ] || die "stylesheet is missing or empty: $CSS_FILE"

require_text() {
  file=$1
  text=$2
  message=$3

  grep -Fq -- "$text" "$file" || die "$message"
}

require_text "$HTML_FILE" '<html lang="en">' 'HTML language declaration is missing'
require_text "$HTML_FILE" '<meta name="viewport" content="width=device-width, initial-scale=1">' 'viewport metadata is missing'
require_text "$HTML_FILE" '<link rel="canonical" href="https://zevarix.github.io/pantheon-local-tools/">' 'canonical URL is missing or changed'
require_text "$HTML_FILE" 'Pantheon work, locally.' 'product-page hero is missing'
require_text "$HTML_FILE" 'install-apt.sh' 'one-command APT install is missing'
require_text "$HTML_FILE" 'dists/stable/InRelease' 'signed APT repository metadata link is missing'
require_text "$HTML_FILE" 'pantheon-local-tools-archive-keyring.gpg' 'APT archive keyring link is missing'
require_text "$HTML_FILE" 'id="faq"' 'FAQ section is missing'
require_text "$HTML_FILE" 'pantheon-local multidev create' 'explicit Multidev creation boundary is missing'
require_text "$HTML_FILE" 'pantheon-local doctor' 'v0.2 doctor workflow is missing'
require_text "$HTML_FILE" 'pantheon-local checkout example-site.dev' 'v0.2 canonical checkout workflow is missing'
require_text "$HTML_FILE" 'pantheon-local estate status --all' 'v0.2 estate-status workflow is missing'
require_text "$HTML_FILE" 'pantheon-local status --format json' 'v0.2 structured status example is missing'
require_text "$HTML_FILE" 'WSL/WSL2' 'supported Windows host wording is missing'
require_text "$HTML_FILE" 'DDEV' 'DDEV support wording is missing'
require_text "$HTML_FILE" 'Lando' 'Lando support wording is missing'
require_text "$HTML_FILE" 'class="terminal-motion-toggle"' 'hero motion pause/play control is missing'
require_text "$HTML_FILE" 'aria-label="Pause hero animation"' 'hero motion control accessible label is missing'
require_text "$HTML_FILE" "hero.classList.toggle('hero--motion-paused')" 'hero motion toggle behavior is missing'

nav_block=$(sed -n '/<nav class="primary-nav"/,/<\/nav>/p' "$HTML_FILE")
[ -n "$nav_block" ] || die 'primary navigation block is missing'

nav_targets=$(
  printf '%s\n' "$nav_block" |
    grep -o 'href="#[^"]*"' |
    sed 's/^href="#//; s/"$//' || true
)

[ -n "$nav_targets" ] || die 'primary navigation has no local section targets'

for target in $nav_targets; do
  require_text "$HTML_FILE" "id=\"$target\"" "primary navigation target #$target has no matching id"
done

require_text "$CSS_FILE" 'a:focus-visible' 'visible keyboard-focus styling is missing'
require_text "$CSS_FILE" '@media (prefers-reduced-motion: reduce)' 'reduced-motion handling is missing'
require_text "$CSS_FILE" '.hero--motion-paused .terminal-session *' 'hero terminal pause styling is missing'
require_text "$CSS_FILE" 'animation-play-state: paused !important;' 'hero animation pause state is missing'
require_text "$CSS_FILE" '@media (max-width: 48rem)' 'mobile layout breakpoint is missing'

printf 'Landing page validation: PASS\n'
