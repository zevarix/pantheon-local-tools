# Homebrew packaging

Pantheon Local Tools is published through a small external Homebrew tap using immutable tagged release artifacts.

The intended tap repository is:

```text
zevarix/homebrew-tap
```

Homebrew maps that GitHub repository to the short tap name `zevarix/tap`. The formula should live at:

```text
Formula/pantheon-local-tools.rb
```

## User installation

For published releases, the preferred one-command installation is:

```bash
brew install zevarix/tap/pantheon-local-tools
```

The explicit formula reference trusts only that formula rather than the entire third-party tap.

Users may also tap first and then install:

```bash
brew tap zevarix/tap
brew install pantheon-local-tools
```

## Formula layout

The formula installs the source payload beneath Homebrew's formula `libexec` directory:

```text
libexec/
  bin/pantheon-local
  libexec/pantheon-local-core
  libexec/pantheon-local-provider-url
  libexec/pantheon-local-pull
  libexec/pantheon-local-status
  VERSION
```

Homebrew then links only `libexec/bin/pantheon-local` into the formula `bin` directory. This preserves the same relative `bin` → `libexec` → `VERSION` resolution contract used by the clone installer and Debian package.

No provider configuration, user configuration, checkout state, or Pantheon credentials are generated during installation.

## Render a release formula

`render-formula.sh` takes four values:

```bash
bash packaging/homebrew/render-formula.sh VERSION URL SHA256 OUTPUT
```

For a release, `VERSION` must equal the repository-root `VERSION` and the `vVERSION` Git tag. `URL` should be the uploaded deterministic GitHub Release source asset URL and `SHA256` must match that exact published asset. Do not use GitHub's automatically generated tag archive for release formula metadata.

Example shape after `v0.1.0` exists:

```bash
VERSION=0.1.0
URL="https://github.com/zevarix/pantheon-local-tools/releases/download/v${VERSION}/pantheon-local-tools-${VERSION}.tar.gz"
SHA256="<verified uploaded release source asset sha256>"
bash packaging/homebrew/render-formula.sh \
  "$VERSION" "$URL" "$SHA256" \
  Formula/pantheon-local-tools.rb
```

Do not publish a formula that points at `main`, a branch archive, or an unverified checksum.

## Validation

The repository test suite performs a local Homebrew installation on macOS CI from a generated local source archive. It verifies:

- formula Ruby syntax;
- source checksum enforcement;
- the Homebrew `libexec` layout;
- command/module executability;
- `pantheon-local version` and `--version` consistency;
- the formula `test do` block; and
- user configuration remaining outside Homebrew-owned paths.

The test skips on hosts where Homebrew is unavailable, while the renderer still receives normal shell syntax and ShellCheck validation.

For each published tap formula, validate the final release URL/checksum with current Homebrew tooling, including a build-from-source install, `brew test`, `brew audit --strict --new --online`, and `brew style`.

## Upgrade and uninstall

A real release candidate is not complete until the tap has been exercised for:

- clean installation;
- upgrade from a previous package revision/version where applicable;
- `brew test` after installation/upgrade; and
- uninstall without deleting `~/.config/pantheon-local-tools/` or checkout-local `.git/pantheon-local-tools/` metadata.

Homebrew owns installed package files only. User configuration and checkout state remain outside package ownership.
