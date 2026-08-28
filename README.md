# Pantheon Local Tools

[![Validate](https://github.com/zevarix/pantheon-local-tools/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/zevarix/pantheon-local-tools/actions/workflows/validate.yml)

**[Project website](https://zevarix.github.io/pantheon-local-tools/)** · [Latest release](https://github.com/zevarix/pantheon-local-tools/releases/latest) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

Pantheon Local Tools is a free, open-source CLI for safer, repeatable Pantheon local-development workflows across **DDEV** and **Lando**.

It is designed to replace machine-specific glue scripts without taking ownership away from Pantheon, Terminus, Git, or the local provider. The shared Pantheon/Terminus core stays provider-neutral, project-owned DDEV/Lando configuration remains authoritative, and ambiguous or destructive situations fail instead of guessing.

The public release line has completed real-provider and real-host validation on macOS, Linux/hosted Ubuntu, and Windows through WSL2. See [`docs/real-integration-validation.md`](docs/real-integration-validation.md) for the evidence model and [`docs/compatibility.md`](docs/compatibility.md) for the supported `0.1.x` contract.

## Quick start

### Prerequisites

Install the tools required by the workflows you intend to use:

- **Git** and **Bash**;
- **Terminus**, authenticated before commands that query Pantheon; and
- at least one supported local provider: **DDEV** or **Lando**.

Pantheon remains authoritative for Terminus installation and authentication:

- [Install and Update Terminus](https://docs.pantheon.io/terminus/install)
- [Create and manage machine tokens](https://docs.pantheon.io/machine-tokens)

Pantheon Local Tools does not store Pantheon machine tokens.

### Install

#### macOS with Homebrew

```bash
brew install zevarix/tap/pantheon-local-tools
```

#### Debian, Ubuntu, or WSL

First complete the one-time fingerprint-verifying repository setup in [`docs/apt-repository.md`](docs/apt-repository.md). After that:

```bash
sudo apt-get update
sudo apt-get install pantheon-local-tools
```

#### Portable clone install

```bash
git clone https://github.com/zevarix/pantheon-local-tools.git
cd pantheon-local-tools
./install.sh
```

The portable installer links `pantheon-local` into `~/.local/bin` by default and does not edit shell startup files. Set `PANTHEON_LOCAL_BIN_DIR` to choose another destination.

Verify the installation with:

```bash
pantheon-local --version
```

### Configure and try a Multidev checkout

Choose a checkout root and, optionally, a default provider:

```bash
pantheon-local config set root ~/sites/pantheon
pantheon-local config set provider ddev
```

Resolve a real existing Pantheon Multidev without changing the filesystem:

```bash
pantheon-local multidev SITE.ENV --dry-run
```

When the plan is correct, create the isolated local checkout:

```bash
pantheon-local multidev SITE.ENV --provider ddev --start
```

Use `lando` instead of `ddev` when that is the project/provider you want.

## Commands

```text
pantheon-local config path
pantheon-local config get KEY
pantheon-local config set KEY VALUE
pantheon-local config unset KEY
pantheon-local config list
pantheon-local config tag get TAG
pantheon-local config tag set TAG DIRECTORY
pantheon-local config tag unset TAG
pantheon-local config tag list

pantheon-local multidev SITE.ENV
  --provider ddev|lando
  --group NAME
  --dry-run
  --start

pantheon-local pull ENV
  --database-only
  --files-only
  --provider ddev|lando

pantheon-local status
pantheon-local version
pantheon-local --version
```

## Core workflows

### Multidev checkouts

`pantheon-local multidev SITE.ENV` clones an **existing** Pantheon Multidev into an isolated local checkout. It does not create, delete, or mutate the remote Pantheon environment.

The command resolves the authoritative Git URL through Terminus, applies user-configured Pantheon Tag routing when present, refuses occupied destinations, configures the selected local provider additively, and finalizes the checkout only after local setup succeeds. `--dry-run` resolves and prints the plan without cloning; `--start` is explicit.

See [`docs/multidev.md`](docs/multidev.md) for the full workflow and safety contract.

### Data pulls

`pantheon-local pull ENV` refreshes local Pantheon data while protecting checked-out Git code.

```bash
pantheon-local pull live
pantheon-local pull test --database-only
pantheon-local pull live --files-only
```

Provider-specific transfer stays delegated to DDEV or Lando. Before and after the provider operation, Pantheon Local Tools verifies that Git `HEAD` and tracked content are unchanged. Database/files provenance is recorded only after provider success and Git-integrity verification.

See [`docs/pull.md`](docs/pull.md) for component selection, provider behavior, and the complete pull safety contract.

### Local status

`pantheon-local status` is a local, read-only inspection command. It can run from the checkout root or a subdirectory and does not contact Pantheon or start/rebuild a provider.

For managed checkouts it reports recorded Pantheon identity, provider, Git state, provider-derived runtime URL when available, and independent database/files provenance. Existing DDEV/Lando Git checkouts are also supported; unavailable Pantheon metadata is reported as not recorded rather than guessed.

See [`docs/status.md`](docs/status.md) for the status contract.

## Configuration

User configuration is managed through `pantheon-local config`; hand-editing is not required.

By default it lives at:

```text
~/.config/pantheon-local-tools/config
```

`XDG_CONFIG_HOME` is respected. `PANTHEON_LOCAL_CONFIG` can override the complete path for automation and testing.

Built-in defaults are:

- `root`: `$HOME/sites/pantheon`
- `provider`: `auto`
- Pantheon Tag mappings: none

Examples:

```bash
pantheon-local config set root ~/work/pantheon
pantheon-local config set provider lando
pantheon-local config tag set "Client Sites" clients
pantheon-local config list
```

Organization-specific Pantheon Tags, directory names, account details, and machine paths belong only in user configuration and are never project defaults.

## Providers and hosts

Supported local providers for the `0.1.x` line are **DDEV** and **Lando**.

Pantheon Local Tools preserves project-owned `.ddev/config.yaml`, `.lando.yml`, services, add-ons, custom tooling, and Compose extensions. Local overrides are additive; if a change cannot be made safely, the tool fails instead of replacing provider configuration.

Supported host environments are:

- macOS;
- Linux; and
- Windows through WSL/WSL2.

On Windows, commands run inside WSL using Linux paths. Native PowerShell and Command Prompt are not initial targets.

See [`docs/local-provider-architecture.md`](docs/local-provider-architecture.md) for provider boundaries and upstream references.

## Safety contract

Pantheon Local Tools is intentionally conservative around developer machines and remote environments:

- existing checkout destinations are never silently overwritten;
- local checkout creation never creates or deletes a remote Pantheon Multidev;
- `pantheon-local pull` never pulls Git code;
- provider/project configuration remains provider-owned;
- provider detection and Pantheon Tag routing fail on ambiguity rather than guessing;
- provider start/rebuild behavior is explicit;
- Pantheon machine tokens are not collected or persisted;
- pull provenance is recorded only after provider success and Git-integrity verification; and
- package installation/removal does not own user configuration or checkout-local state.

The complete compatibility and safety guarantees for the `0.1.x` line are in [`docs/compatibility.md`](docs/compatibility.md).

## Distribution

Pantheon Local Tools ships through several equivalent distribution paths built from the same tagged project contents:

- the portable clone installer;
- [Homebrew](packaging/homebrew/README.md) through `zevarix/tap`;
- downloadable architecture-independent `.deb` release artifacts; and
- the [signed APT repository](docs/apt-repository.md) for Debian, Ubuntu, and WSL.

The **[project website](https://zevarix.github.io/pantheon-local-tools/)** and signed APT repository intentionally share one GitHub Pages origin. Humans get the product page at `/`; APT consumes the signed repository metadata and package indexes beneath that same origin.

Release artifacts and package metadata are tied to immutable tagged releases. See [`docs/releasing.md`](docs/releasing.md) for the maintainer procedure.

## Development

The installed `bin/pantheon-local` command is a small dispatcher. Command implementations live under `libexec/`, keeping workflow slices independently testable while preserving one public CLI.

Run the integration suite with:

```bash
for test in tests/test-*.sh; do
  bash "$test"
done
```

Run ShellCheck when available:

```bash
shellcheck bin/pantheon-local libexec/pantheon-local-* install.sh tests/test-*.sh packaging/debian/*.sh packaging/homebrew/*.sh packaging/release/*.sh
```

CI runs syntax validation, ShellCheck, and the shell integration suite on Ubuntu and macOS. The project intentionally avoids Bash 4-only features so the shipped shell code remains compatible with the older Bash supplied by macOS as well as modern Bash on Linux and WSL.

## Documentation

- [`docs/multidev.md`](docs/multidev.md) — Multidev checkout behavior and safety
- [`docs/pull.md`](docs/pull.md) — database/files pull behavior and Git protection
- [`docs/status.md`](docs/status.md) — read-only checkout inspection contract
- [`docs/local-provider-architecture.md`](docs/local-provider-architecture.md) — DDEV/Lando boundary and provider architecture
- [`docs/compatibility.md`](docs/compatibility.md) — supported `0.1.x` public contract
- [`docs/apt-repository.md`](docs/apt-repository.md) — signed APT client trust, rotation, and recovery
- [`docs/real-integration-validation.md`](docs/real-integration-validation.md) — real-host/provider validation runbook
- [`docs/releasing.md`](docs/releasing.md) — maintainer release procedure

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT license. See [`LICENSE`](LICENSE).

## Independence

Pantheon Local Tools is an independent open-source project. It is not an official Pantheon Systems project, and Pantheon remains authoritative for its platform, Terminus, and published product documentation.
