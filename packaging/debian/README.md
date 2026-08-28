# Debian package

Pantheon Local Tools can be packaged as an architecture-independent Debian package for Debian, Ubuntu, and WSL/WSL2 environments.

The package contains shell code only, so its architecture is `all`.

## Build

From the repository root on a Debian-family system with `dpkg-deb` available:

```bash
bash packaging/debian/build-deb.sh
```

The default output is:

```text
dist/pantheon-local-tools_<VERSION>_all.deb
```

Pass an output directory as the first argument to choose another location.

The package version comes directly from the repository-root `VERSION` file. Release packaging must therefore be built from the exact tagged release whose `VERSION` matches the tag.

## Layout

The package installs the application under:

```text
/usr/lib/pantheon-local-tools/
```

and provides the command through a relative symlink:

```text
/usr/bin/pantheon-local -> ../lib/pantheon-local-tools/bin/pantheon-local
```

Keeping `bin/`, `libexec/`, and `VERSION` together preserves the same relative module/version resolution used by the clone installer and future Homebrew formula.

## Install a downloaded package

For a `.deb` downloaded from a GitHub Release:

```bash
sudo apt install ./pantheon-local-tools_<VERSION>_all.deb
```

Using `apt install ./...` is preferred over invoking `dpkg -i` directly because APT handles declared dependencies.

## Runtime dependencies

The package declares:

- `bash`
- `git`

Provider-specific tools are intentionally not package dependencies. Install Terminus, DDEV, or Lando according to the workflows you actually use and their upstream installation guidance.

## User state

Package installation does not create Pantheon Local Tools user configuration, provider project files, or Pantheon credentials.

User configuration remains under the existing XDG/home path, normally:

```text
~/.config/pantheon-local-tools/config
```

Package removal does not own that file and therefore must not delete it. Checkout-local state under `.git/pantheon-local-tools/` is likewise outside package ownership.

## Signed APT repository

The hosted APT repository is a separate distribution layer from the downloadable `.deb` and is published at:

```text
https://zevarix.github.io/pantheon-local-tools
```

End-user key verification, `/etc/apt/keyrings` installation, deb822 `Signed-By` setup, removal, signing-key rotation, revocation, and recovery procedures are documented in [`docs/apt-repository.md`](../../docs/apt-repository.md).

Repository tooling uses a conventional Debian archive layout:

```text
pool/main/p/pantheon-local-tools/
  pantheon-local-tools_<VERSION>_all.deb

dists/stable/
  Release
  InRelease
  Release.gpg
  main/binary-all/
    Packages
    Packages.gz

pantheon-local-tools-archive-keyring.gpg
```

`Architecture: all` has its own package index. The `Release` metadata declares `Architectures: all`, `Components: main`, `Suite: stable`, and `Codename: stable`.

### Build repository metadata

Build the `.deb` first, then create a fresh repository tree:

```bash
PACKAGE=$(bash packaging/debian/build-deb.sh)
SOURCE_DATE_EPOCH=<release-epoch> \
  bash packaging/debian/build-apt-repository.sh \
    dist/apt-repository \
    "$PACKAGE"
```

The repository builder:

- accepts one or more `pantheon-local-tools` packages;
- requires every package to use `Architecture: all`;
- rejects duplicate package versions;
- requires at least one input package whose version matches the checkout's root `VERSION`;
- writes package files under `pool/`;
- indexes every supplied released version with `dpkg-scanpackages --multiversion` and generates `Packages` plus deterministic `Packages.gz`;
- covers both indexes with SHA-256 and SHA-512 entries in `Release`; and
- produces reproducible repository metadata when `SOURCE_DATE_EPOCH` is fixed.

The output path must not already exist. This prevents stale indexes or packages from being silently mixed into a new publication tree.

For release publication automation, `PANTHEON_LOCAL_APT_CURRENT_VERSION` may explicitly select the version that must be present in the generated repository. Normal direct use defaults to the repository-root `VERSION`.

### Assemble from published releases

`build-published-apt-repository.sh` builds the publication input from GitHub Releases rather than rebuilding historical packages:

```bash
bash packaging/debian/build-published-apt-repository.sh \
  dist/apt-repository \
  zevarix/pantheon-local-tools \
  VERSION
```

For every stable release up to and including the target version, the assembler:

- downloads the versioned `.deb` plus that release's `SHA256SUMS`;
- verifies the package bytes against the published checksum;
- verifies package name, version, and `Architecture: all` metadata;
- rejects a target version that is not a stable published release; and
- feeds all verified historical packages into the multiversion repository builder.

When `SOURCE_DATE_EPOCH` is not supplied, the target GitHub Release publication time is used so repeated assembly of the same target produces stable unsigned repository metadata.

### Sign repository metadata

Signing is intentionally separate from repository generation:

```bash
bash packaging/debian/sign-apt-repository.sh \
  dist/apt-repository \
  FULL_SIGNING_KEY_FINGERPRINT
```

The signer requires the corresponding secret key to already exist in the caller's GPG keyring. It creates:

- `dists/stable/InRelease`;
- `dists/stable/Release.gpg`; and
- `pantheon-local-tools-archive-keyring.gpg`.

It immediately verifies both signatures using the exported public keyring.

Do **not** store a production private signing key, passphrase, or exported secret-key material in this repository, release assets, generated repository content, workflow logs, or public issue comments.

CI validates the signing path with ephemeral throwaway keys. `PANTHEON_LOCAL_APT_SIGNING_PASSPHRASE` optionally supplies a passphrase to GPG through loopback pinentry, allowing the production signing subkey stored in Actions secrets to remain passphrase-protected.

When multiple usable signing subkeys exist during a rotation overlap, set `PANTHEON_LOCAL_APT_EXACT_SIGNING_KEY=1` and pass the exact signing-subkey fingerprint. The signer appends GPG's exact-key selector (`!`) so publication never depends on implicit subkey choice. Production Actions can supply that fingerprint through the optional `APT_SIGNING_SUBKEY_FINGERPRINT` repository secret; with no such secret, the existing single-subkey behavior remains unchanged.

Production key creation, secure backup, rotation/recovery policy, and publication credentials remain operational concerns documented in [`docs/apt-repository.md`](../../docs/apt-repository.md), not source-controlled secrets.

### Client trust

Clients use a dedicated keyring under `/etc/apt/keyrings` and APT's `Signed-By` mechanism. The project does not use deprecated `apt-key` or add the archive key to global APT trust.

The live deb822 source is:

```text
Types: deb
URIs: https://zevarix.github.io/pantheon-local-tools
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/pantheon-local-tools.gpg
```

Do not install the keyring without verifying the documented primary fingerprint first. The complete copy/paste-safe client procedure and current public fingerprint are in [`docs/apt-repository.md`](../../docs/apt-repository.md).

### Publication boundary

`.github/workflows/publish-apt-repository.yml` performs a real publication dry run on relevant pull requests with an ephemeral key against the latest already-published stable release. Stable release events and manual dispatches use the configured production signing-subkey secrets, upload the generated static archive as a GitHub Pages artifact, and deploy it through the `github-pages` environment.

GitHub Pages is enabled with **Source: GitHub Actions**, and the initial v0.1.0 repository has been published and signature-verified through the real public URL. The workflow intentionally assembles historical `.deb` files from their published GitHub Release assets rather than rebuilding old packages.

`.github/workflows/validate-published-apt.yml` exercises the public HTTPS repository on clean hosted Ubuntu, including archive fingerprint verification, `apt update`, candidate discovery, install, reinstall with user-configuration preservation, and uninstall. The same public v0.1.0 path has also completed real WSL2 validation.

The first real previous-version to newer-version package upgrade remains deferred until a second published Debian package exists.
