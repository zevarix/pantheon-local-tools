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

A downloadable `.deb` and a hosted APT repository are separate distribution layers.

The initial package can be attached directly to a GitHub Release. A later signed APT repository can add normal `apt update` / `apt install pantheon-local-tools` upgrade discovery after repository hosting, signing/keyring policy, metadata publication, and rotation/recovery procedures are established.

The hosted APT repository is intentionally not required to ship the first `.deb`.
