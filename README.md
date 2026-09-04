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

```bash
curl -fsSL https://raw.githubusercontent.com/zevarix/pantheon-local-tools/main/install-apt.sh | bash
```

The helper verifies the published archive fingerprint before installing the dedicated APT keyring/source and package. See [`docs/apt-repository.md`](docs/apt-repository.md) for the manual/auditable setup and trust model.

#### Portable clone install

```bash
git clone https://github.com/zevarix/pantheon-local-tools.git
cd pantheon-local-tools
./install.sh
```

The portable installer links `pantheon-local` into `~/.local/bin` by default and does not edit shell startup files. Set `PANTHEON_LOCAL_BIN_DIR` to choose another destination.

Verify the installation and discover the command surface with:

```bash
pantheon-local --version
pantheon-local help
```

### Configure and try a Multidev checkout

For guided first-run setup, run:

```bash
pantheon-local config init
```

The setup uses the current effective checkout root/provider values, lets you choose `auto`, DDEV, or Lando, summarizes the result, and confirms before writing. Experienced users and scripts can configure one or both values without prompts:

```bash
pantheon-local config init --root ~/sites/pantheon --provider ddev
```

The granular configuration commands remain available when you want direct control:

```bash
pantheon-local config set root ~/sites/pantheon
pantheon-local config set provider ddev
```

Optional Pantheon Tag profiles describe strategy-aware configuration workflows without hard-coding organization names or config paths:

```bash
pantheon-local config tag set 'Example Group' example-group
pantheon-local config tag profile set 'Example Group' config-strategy full-export
pantheon-local config tag profile set 'Example Group' config-path config/project-export
```

See [`docs/configuration.md`](docs/configuration.md) for the Git-compatible profile contract, including `full-export` versus `overlay-delta` semantics.

Resolve a real existing Pantheon Multidev without changing the filesystem:

```bash
pantheon-local multidev SITE.ENV --dry-run
```

When the plan is correct, create the isolated local checkout:

```bash
pantheon-local multidev SITE.ENV --provider ddev --start
```

Use `lando` instead of `ddev` when that is the project/provider you want.

For a PLT-managed Drupal checkout, inspect the bootstrap plan before replacing local database data:

```bash
cd /path/to/the/checkout
pantheon-local setup --dry-run
```

Then run the provider-aware Drupal bootstrap explicitly:

```bash
pantheon-local setup
```

Setup starts the selected provider, runs Composer inside that provider, reuses the guarded database-only pull from the checkout's recorded Pantheon environment, then runs `drush updb -y` and `drush cr`. See [`docs/setup.md`](docs/setup.md) for its mutation and retry contract.

Inspect the recorded Tag profile's configuration boundary without exporting anything:

```bash
pantheon-local readiness
```

For `full-export`, readiness uses the configured path, verifies it against Drupal's runtime config-sync path, reports `drush config:status`, Config Ignore module state when detectable, and the Git working tree. Differences are review states rather than automatic failures.

For `overlay-delta`, readiness validates that the configured protected partial path exists and remains inside the project root, reports Git state, performs no provider/Drush call, and exits nonzero with `Owning validation: unavailable` rather than inventing drift/readiness semantics. Missing YAML, directory size, and file count are not treated as drift. Neither strategy performs `drush cex` / `config:export`. See [`docs/readiness.md`](docs/readiness.md).

When a `full-export` readiness review is complete and you deliberately want to mutate tracked configuration files, use the separate export command:

```bash
pantheon-local config export
```

Interactive use confirms before mutation. Automation must supply `--yes`. The configured export path must be Git-clean before export, `overlay-delta` is refused, and PLT never stages, commits, pushes, or modifies a remote Pantheon environment. See [`docs/config-export.md`](docs/config-export.md).

## Commands

Run `pantheon-local help` or `pantheon-local --help` for the complete in-tool command reference.

```text
pantheon-local help
pantheon-local --help

pantheon-local config init [--root PATH] [--provider auto|ddev|lando]
pantheon-local config path
pantheon-local config get KEY
pantheon-local config set KEY VALUE
pantheon-local config unset KEY
pantheon-local config list
pantheon-local config tag get TAG
pantheon-local config tag set TAG DIRECTORY
pantheon-local config tag unset TAG
pantheon-local config tag list
pantheon-local config tag profile get TAG PROPERTY
pantheon-local config tag profile set TAG PROPERTY VALUE
pantheon-local config tag profile unset TAG PROPERTY
pantheon-local config tag profile list [TAG]
pantheon-local config export [--provider ddev|lando] [--yes]

pantheon-local multidev SITE.ENV
  --provider ddev|lando
  --group NAME
  --dry-run
  --start

pantheon-local setup
  --provider ddev|lando
  --dry-run

pantheon-local readiness
  --provider ddev|lando

pantheon-local pull ENV
  --database-only
  --files-only
  --provider ddev|lando

pantheon-local status
pantheon-local version
pantheon-local --version
```

Focused help remains available for nontrivial commands, for example `pantheon-local config help`, `pantheon-local config tag profile --help`, `pantheon-local config export --help`, `pantheon-local multidev --help`, `pantheon-local setup --help`, `pantheon-local readiness --help`, `pantheon-local pull --help`, and `pantheon-local status --help`.

## Core workflows

### Multidev checkouts

`pantheon-local multidev SITE.ENV` clones an **existing** Pantheon Multidev into an isolated local checkout. It does not create, delete, or mutate the remote Pantheon environment.

The command resolves the authoritative Git URL through Terminus, applies user-configured Pantheon Tag routing when present, refuses occupied destinations, configures the selected local provider additively, and finalizes the checkout only after local setup succeeds. `--dry-run` resolves and prints the plan without cloning; `--start` is explicit and continues to mean provider start only.

See [`docs/multidev.md`](docs/multidev.md) for the full workflow and safety contract.

### Drupal checkout setup

`pantheon-local setup` bootstraps an existing **PLT-managed Drupal checkout** using the Pantheon environment recorded when the checkout was created. It refuses to infer that source from the Git branch or silently substitute Live.

The required order is provider start → provider-owned `composer install` → existing guarded `pull --database-only` → provider-owned `drush updb -y` → provider-owned `drush cr`. The pipeline stops on the first failed mutating step and records the failed/current/completed bootstrap step in checkout-local PLT state.

`--dry-run` performs local preflight and prints the exact plan without starting the provider, running Composer/Drush, pulling data, or changing bootstrap state. A real setup run is explicitly local and mutating: Composer may access the network and run project scripts, the local database is replaced from the recorded Pantheon environment, and Drush updates local database/cache state.

Setup does not pull files or Git code, export Drupal configuration, push to Pantheon, or rewrite provider-owned base configuration. `multidev --start` remains start-only; setup is a separate command.

See [`docs/setup.md`](docs/setup.md) for provider mappings, preflight, failure/retry behavior, upstream references, and state fields.

### Drupal configuration readiness

`pantheon-local readiness` is a standalone, strategy-aware inspection for the current PLT-managed checkout. The recorded Tag must declare either `config-strategy=full-export` or `config-strategy=overlay-delta` plus a configured `config-path`.

For `full-export`, readiness does not start/rebuild the provider. It uses provider-owned Drush to verify that Drupal's runtime config-sync path corresponds to the configured profile path, inspect active-versus-exported configuration differences, and detect whether Config Ignore is enabled when that module-state query is available. It also compares Git state before and after delegated inspection so a supposedly read-only command cannot silently mutate source.

Synchronized full-export configuration and a clean tree report `ready`. Configuration differences and a pre-existing modified tree report review-required states but still exit successfully when the inspection itself is complete. Provider/Drush failures, path mismatch, unsupported/incomplete profiles, or Git changes caused during delegated inspection fail nonzero.

For `overlay-delta`, readiness recognizes the configured path as a protected partial override set. It validates that the directory exists and stays physically inside the Git project root, reports the current Git working tree, and performs no provider or Drush command while a reliable owning validation mechanism is unavailable. Missing YAML, directory size, and file count do not imply drift. The command reports `Owning validation: unavailable` / `Readiness: unavailable` and exits nonzero rather than claiming success.

No configuration export is performed for either strategy. Config Ignore's matching rules are not reimplemented, and full-export semantics are never applied to an overlay/delta directory.

See [`docs/readiness.md`](docs/readiness.md) for the complete strategy, Config Ignore, path-containment, Git-integrity, and exit-status contract.

### Explicit Drupal configuration export

`pantheon-local config export [--provider ddev|lando] [--yes]` is the deliberate tracked-source mutation boundary for `full-export` profiles. It is separate from readiness, status, setup, Multidev start, and Tag matching so a reported configuration difference can never turn itself into an automatic export.

Before mutation, PLT requires the configured export path to be Git-clean, completes the normal full-export readiness inspection, requires Config Ignore module-state inspection to succeed, prints the mutation plan, and confirms interactively unless `--yes` was supplied. Unrelated dirty files elsewhere in the checkout are preserved.

The actual mutation is provider-owned `drush config:export -y`. PLT does not pass Drush staging/commit options and does not stage, commit, push, or perform a Pantheon remote write. `overlay-delta` is refused before provider/Drush invocation.

After the export attempt, PLT reports created/changed/deleted files under the configured path plus the complete Git status. If Drush fails after writing files, PLT preserves and reports the partial local state and exits nonzero rather than attempting an unsafe automatic rollback.

See [`docs/config-export.md`](docs/config-export.md) for confirmation, Config Ignore, failure/retry, provider, and Git-safety details.

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

For managed checkouts it reports recorded Pantheon identity, provider, Git state, provider-derived runtime URL when available, independent database/files provenance, and the latest recorded Drupal bootstrap status/step/timestamp. Existing DDEV/Lando Git checkouts are also supported; unavailable Pantheon/bootstrap metadata is reported as not recorded rather than guessed.

See [`docs/status.md`](docs/status.md) for the status contract.

## Configuration

User configuration is managed through `pantheon-local config`; hand-editing is not required.

For a human first run, `pantheon-local config init` guides root/provider selection and writes only after all selected values validate and you confirm the summary. Supplying `--root` and/or `--provider` makes the same command non-interactive; omitted values remain unchanged. The existing `config get/set/unset/list` commands remain the granular scriptable interface.

By default configuration lives at:

```text
~/.config/pantheon-local-tools/config
```

`XDG_CONFIG_HOME` is respected. `PANTHEON_LOCAL_CONFIG` can override the complete path for automation and testing.

Built-in defaults are:

- `root`: `$HOME/sites/pantheon`
- `provider`: `auto`
- Pantheon Tag mappings: none
- Pantheon Tag profile properties: none

`provider=auto` detects the checkout's project configuration after clone: `.ddev/config.yaml` selects DDEV and `.lando.yml` selects Lando. If detection is ambiguous, the tool refuses to guess.

Pantheon Tag routing remains the identity anchor for profile configuration. An existing Tag route may optionally declare:

- `config-strategy=full-export` for complete exported configuration;
- `config-strategy=overlay-delta` for a protected site-specific delta/override set; and
- a validated relative `config-path` appropriate to that project.

Profile settings remain declarative. They do not themselves run Drupal, export config, start providers, pull data, or mutate Pantheon. Commands that consume them apply separate safety contracts. `pantheon-local readiness` consumes both strategy labels: full-export can complete provider/Drush inspection, while overlay-delta currently reports its protected boundary and fails closed when owning validation is unavailable. `pantheon-local config export` consumes the same profile only as a separate explicit mutation action and supports `full-export` only.

Examples:

```bash
pantheon-local config init
pantheon-local config init --provider lando
pantheon-local config set root ~/work/pantheon
pantheon-local config tag set "Client Sites" clients
pantheon-local config tag profile set "Client Sites" config-strategy full-export
pantheon-local config tag profile set "Client Sites" config-path config/project-export
pantheon-local config tag profile list "Client Sites"
pantheon-local config list
```

The persistent representation continues to be one Git-compatible configuration file managed through Git's own `git config --file` parser/writer. No YAML/JSON/TOML profile store is introduced. See [`docs/configuration.md`](docs/configuration.md) for validation, unset behavior, and strategy boundaries.

Organization-specific Pantheon Tags, directory names, config strategies/paths, account details, and machine paths belong only in user configuration and are never project defaults.

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
- `pantheon-local setup` uses only the checkout's recorded Pantheon environment for its database refresh and never infers Live/current-branch semantics;
- setup runs Composer inside the selected provider and stops immediately when provider start, Composer, database pull, `updb`, or cache rebuild fails;
- setup does not pull files/Git code, export config, push to Pantheon, or change the meaning of `multidev --start`;
- `pantheon-local readiness` does not start/rebuild providers or export config and refuses mismatched/unsupported profile semantics;
- full-export readiness reports Config Ignore conservatively without hiding drift or duplicating Config Ignore matching rules;
- readiness rejects configured directories that escape the Git project root through filesystem links;
- readiness verifies delegated full-export inspection does not change Git state;
- overlay-delta readiness never interprets missing YAML, directory size, or file count as drift;
- overlay-delta readiness does not invoke providers/Drush while owning validation is unavailable and exits nonzero rather than claiming readiness;
- `pantheon-local config export` is explicit, confirmed/acknowledged, supports `full-export` only, and never runs as a readiness/setup/status/start side effect;
- config export requires the configured export path to be Git-clean, never auto-stages/commits/pushes, and preserves/reports partial local changes after a failed provider export;
- provider/project configuration remains provider-owned;
- provider detection and Pantheon Tag routing fail on ambiguity rather than guessing;
- unsupported Tag profile strategies and unsafe project-relative config paths fail instead of being guessed;
- an `overlay-delta` profile never implies that its path is a complete Drupal export or may be overwritten by a blanket export;
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
shellcheck bin/pantheon-local libexec/pantheon-local-* install.sh install-apt.sh tests/test-*.sh packaging/debian/*.sh packaging/homebrew/*.sh packaging/release/*.sh
```

CI runs syntax validation, ShellCheck, and the shell integration suite on Ubuntu and macOS. The project intentionally avoids Bash 4-only features so the shipped shell code remains compatible with the older Bash supplied by macOS as well as modern Bash on Linux and WSL.

## Documentation

- [`docs/configuration.md`](docs/configuration.md) — Git-compatible user configuration and Pantheon Tag profile strategies
- [`docs/multidev.md`](docs/multidev.md) — Multidev checkout behavior and safety
- [`docs/setup.md`](docs/setup.md) — provider-aware Drupal checkout bootstrap, failure/retry behavior, and local mutation boundaries
- [`docs/readiness.md`](docs/readiness.md) — strategy-aware Drupal config readiness, overlay fail-closed reporting, Config Ignore, path containment, Git-integrity, and exit semantics
- [`docs/config-export.md`](docs/config-export.md) — explicit full-export mutation, confirmation, Config Ignore authority, change reporting, and failure/retry behavior
- [`docs/pull.md`](docs/pull.md) — database/files pull behavior and Git protection
- [`docs/status.md`](docs/status.md) — read-only checkout inspection contract
- [`docs/local-provider-architecture.md`](docs/local-provider-architecture.md) — DDEV/Lando boundary and provider architecture
- [`docs/compatibility.md`](docs/compatibility.md) — supported `0.1.x` public contract
- [`docs/apt-repository.md`](docs/apt-repository.md) — signed APT client trust, one-command install, rotation, and recovery
- [`docs/real-integration-validation.md`](docs/real-integration-validation.md) — real-host/provider validation runbook
- [`docs/releasing.md`](docs/releasing.md) — maintainer release procedure

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT license. See [`LICENSE`](LICENSE).

## Independence

Pantheon Local Tools is an independent open-source project. It is not an official Pantheon Systems project, and Pantheon remains authoritative for its platform, Terminus, and published product documentation.
