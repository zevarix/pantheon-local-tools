#!/usr/bin/env bash
set -euo pipefail

PROGRAM_NAME='pantheon-local-tools Homebrew renderer'

die() {
  printf '%s: %s\n' "$PROGRAM_NAME" "$*" >&2
  exit 1
}

[ "$#" -eq 4 ] || die 'usage: render-formula.sh VERSION URL SHA256 OUTPUT'
VERSION=$1
URL=$2
SHA256=$3
OUTPUT=$4

[ -n "$VERSION" ] || die 'VERSION cannot be empty'
[ -n "$URL" ] || die 'URL cannot be empty'
printf '%s\n' "$SHA256" | LC_ALL=C grep -Eq '^[0-9a-fA-F]{64}$' || die 'SHA256 must contain exactly 64 hexadecimal characters'
case "$VERSION$URL$OUTPUT" in
  *$'\n'*|*$'\r'*) die 'arguments cannot contain newlines' ;;
esac

escape_ruby_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

VERSION_ESCAPED=$(escape_ruby_string "$VERSION")
URL_ESCAPED=$(escape_ruby_string "$URL")
SHA256_NORMALIZED=$(printf '%s' "$SHA256" | tr '[:upper:]' '[:lower:]')
OUTPUT_DIR=${OUTPUT%/*}
[ "$OUTPUT_DIR" != "$OUTPUT" ] || OUTPUT_DIR='.'
mkdir -p "$OUTPUT_DIR"

cat > "$OUTPUT" <<EOF
class PantheonLocalTools < Formula
  desc "Provider-neutral local development helpers for Pantheon"
  homepage "https://github.com/zevarix/pantheon-local-tools"
  url "$URL_ESCAPED"
  version "$VERSION_ESCAPED"
  sha256 "$SHA256_NORMALIZED"
  license "MIT"

  depends_on "git"

  def install
    libexec.install "bin", "libexec", "VERSION", "LICENSE", "README.md"
    bin.install_symlink libexec/"bin/pantheon-local"
  end

  test do
    assert_match "pantheon-local #{version}", shell_output("#{bin}/pantheon-local --version")

    ENV["PANTHEON_LOCAL_CONFIG"] = testpath/"config"
    system bin/"pantheon-local", "config", "set", "provider", "lando"
    assert_equal "lando", shell_output("#{bin}/pantheon-local config get provider").strip
  end
end
EOF

printf '%s\n' "$OUTPUT"
