#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools canonical source compressor'
CANONICAL_GZIP_IMAGE='ubuntu@sha256:a853f94d226358a79c740cfc7bce0c289748f3fe3488d921d038ccd752c61b60'
CANONICAL_GZIP_PLATFORM='linux/amd64'

fail() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail 'Docker is required for canonical release compression'

exec docker run \
  --rm \
  --platform "$CANONICAL_GZIP_PLATFORM" \
  --network none \
  -i \
  "$CANONICAL_GZIP_IMAGE" \
  gzip -n
