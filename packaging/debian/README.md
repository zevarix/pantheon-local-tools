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

The hosted APT repository is a separate distribution layer from the downloadable `.deb`.

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

CI validates the signing path with an ephemeral throwaway key. Production key creation, secure backup, rotation/recovery policy, and publication credentials are separate operational concerns.

### Client trust

The final public repository will use a dedicated keyring under `/etc/apt/keyrings` and APT's `Signed-By` mechanism. It must not use deprecated `apt-key` or add the archive key to global APT trust.

The intended deb822 source shape is:

```text
Types: deb
URIs: <APT_REPOSITORY_URL>
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/pantheon-local-tools.gpg
```

The public repository URL and production key installation commands are documented only after the repository is actually published and verified.

### Publication boundary

Repository hosting and production signing are tracked separately from deterministic packaging. The current publication plan is an Actions-built static archive on the project's GitHub Pages site, with historical released `.deb` files retained so future upgrade and downgrade/reinstall tests remain possible.

The first real package upgrade remains deferred until a second published Debian package exists.
