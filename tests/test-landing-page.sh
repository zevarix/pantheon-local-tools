#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$REPO_ROOT/packaging/debian/validate-landing-page.sh"
HTML="$REPO_ROOT/packaging/debian/apt-index.html"
CSS="$REPO_ROOT/packaging/debian/apt-index.css"

fail() {
  printf 'test-landing-page: %s\n' "$*" >&2
  exit 1
}

bash "$VALIDATOR" "$HTML" "$CSS" >/dev/null ||
  fail 'current landing page did not pass validation'

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

BROKEN_HTML="$TMP_DIR/apt-index.html"
cp "$HTML" "$BROKEN_HTML"

sed 's/ id="faq"//' "$HTML" > "$BROKEN_HTML"

if bash "$VALIDATOR" "$BROKEN_HTML" "$CSS" >/dev/null 2>&1; then
  fail 'validator accepted a primary-nav target with no matching section id'
fi

printf 'test-landing-page: PASS\n'
