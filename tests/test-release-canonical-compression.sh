#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)
COMPRESSOR="$REPO_ROOT/packaging/release/compress-source-canonical.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file_eq() { cmp "$1" "$2" >/dev/null 2>&1 || fail "files differ: $1 $2"; }

[ -r "$COMPRESSOR" ] || fail 'canonical source compressor is missing'
REAL_GZIP=$(command -v gzip) || fail 'gzip is required for canonical compression contract test'
MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
: "${DOCKER_ARGS_LOG:?}"
: "${REAL_GZIP:?}"
printf '%s\n' "$@" > "$DOCKER_ARGS_LOG"
exec "$REAL_GZIP" -n
MOCK
chmod +x "$MOCK_BIN/docker"

printf 'canonical-compression-fixture\n' > "$TMP_ROOT/input.tar"
export DOCKER_ARGS_LOG="$TMP_ROOT/docker-args"
export REAL_GZIP
PATH="$MOCK_BIN:$PATH" bash "$COMPRESSOR" < "$TMP_ROOT/input.tar" > "$TMP_ROOT/one.gz"
cp "$DOCKER_ARGS_LOG" "$TMP_ROOT/docker-args-one"
PATH="$MOCK_BIN:$PATH" bash "$COMPRESSOR" < "$TMP_ROOT/input.tar" > "$TMP_ROOT/two.gz"

cat > "$TMP_ROOT/expected-args" <<'EOF'
run
--rm
--platform
linux/amd64
--network
none
-i
ubuntu@sha256:a853f94d226358a79c740cfc7bce0c289748f3fe3488d921d038ccd752c61b60
gzip
-n
EOF

assert_file_eq "$TMP_ROOT/docker-args-one" "$TMP_ROOT/expected-args"
assert_file_eq "$DOCKER_ARGS_LOG" "$TMP_ROOT/expected-args"
assert_file_eq "$TMP_ROOT/one.gz" "$TMP_ROOT/two.gz"

gzip -dc "$TMP_ROOT/one.gz" > "$TMP_ROOT/roundtrip.tar"
assert_file_eq "$TMP_ROOT/input.tar" "$TMP_ROOT/roundtrip.tar"

printf 'canonical release compression tests passed\n'
