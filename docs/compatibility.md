# v0.1 Compatibility Contract

Pantheon Local Tools is pre-1.0 software, but the first public release still needs a clear contract so users, shell scripts, Homebrew, Debian packaging, and future maintainers know what may change safely.

This document defines the supported public surface for the `0.1.x` release line.

## Version source

`VERSION` at the repository root is the single source of truth for the project version.

The CLI exposes it through both:

```bash
pantheon-local version
pantheon-local --version
```

Both print:

```text
pantheon-local VERSION
```

Development snapshots use a SemVer prerelease value such as `0.1.0-dev`. A tagged release must contain the exact release value (for example `0.1.1`) in `VERSION`, and the Git tag must match it with a leading `v` (`v0.1.1`).

## Public command surface

The following commands/options are public for `0.1.x`:

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

Running `pantheon-local` with no arguments shows the same top-level command reference as `pantheon-local help` / `pantheon-local --help`. Focused help routes such as `pantheon-local config help`, `pantheon-local config init --help`, `pantheon-local multidev --help`, `pantheon-local pull --help`, and `pantheon-local status --help` are also supported discovery surfaces.

New commands and additive options may be introduced in a compatible `0.1.x` release when they do not change existing command meaning.

## Configuration contract

The following user configuration concepts are public:

- `root` — absolute local root for Pantheon checkouts;
- `provider` — `auto`, `ddev`, or `lando`;
- Pantheon Tag-to-directory mappings managed through `config tag`.

`pantheon-local config init` is a convenience layer over the same configuration model. With no flags in a terminal, it guides root/provider selection, validates all proposed values, summarizes them, confirms before writing, and uses the normal configuration setters. With `--root` and/or `--provider`, it is non-interactive and changes only values explicitly supplied by the caller. Existing `config get/set/unset/list/path` and `config tag` commands remain first-class granular controls.

The default configuration location follows XDG conventions as documented by the CLI/README. `PANTHEON_LOCAL_CONFIG` remains the supported complete-path override for automation/testing.

The Git-compatible on-disk representation is intentionally simple, but users should prefer the CLI rather than depending on undocumented internal key names.

## Provider contract

DDEV and Lando are the supported local providers for `0.1.x`.

Provider-owned project configuration remains authoritative. Pantheon Local Tools is additive and must not silently replace or strip existing provider services, tooling, add-ons, proxy/custom-hostname configuration, or custom Compose definitions.

When stored configuration uses `provider=auto`, provider selection is based on project configuration after checkout (`.ddev/config.yaml` versus `.lando.yml`), not simply on which provider binaries are installed. Ambiguous detection fails rather than guessing.

A provider-specific implementation detail may change in a patch release when the user-visible command contract and safety properties remain the same.

## Safety contract

A compatible `0.1.x` release must preserve these properties:

- never overwrite an existing multidev checkout;
- never create/delete a Pantheon multidev as a side effect of local checkout creation;
- never pull Git code as part of `pantheon-local pull`;
- never infer a pull source from the current Git branch when the user supplied an environment;
- never record successful pull provenance before provider success and Git-integrity verification;
- never collect or persist Pantheon machine tokens;
- never start/rebuild a provider unless the user requested an operation that explicitly permits it;
- never mutate provider configuration merely to discover a runtime URL;
- fail rather than guess on ambiguous provider or configured Tag routing;
- keep help/read-only discovery surfaces free of provider startup, authentication, or filesystem/project mutation; and
- validate all guided `config init` selections before writing so an invalid later value cannot leave a partial configuration update.

Safety tightening that converts a previously ambiguous/unsafe case into an explicit failure is considered compatible when documented in release notes.

## Local checkout state

`.git/pantheon-local-tools/state` is local metadata, not application configuration and not a file users should commit.

Its schema is not a general-purpose external API. However, upgrades must preserve/migrate state created by earlier supported versions rather than silently discarding known provenance or checkout identity.

In particular, the legacy `data.source` migration to independent database/files provenance demonstrates the expected upgrade behavior.

## Human-readable output

Normal command output is designed for developers and may gain additional labeled fields in patch releases. Existing labels should not be casually renamed or removed within `0.1.x`.

The text output is **not** yet a stable machine-readable API. Scripts that require a formal structured output format should wait for an explicitly documented JSON/porcelain interface rather than parsing incidental spacing.

Exact non-zero numeric exit codes are not part of the `0.1.x` contract; success is exit `0`, failure is non-zero.

## Packaging contract

Homebrew, Debian packages, the signed APT repository, and the clone installer must package the same tagged project contents and report the same `VERSION`.

Package installation/uninstallation must not:

- alter Pantheon credentials;
- rewrite user project files or provider configuration;
- delete the user's Pantheon Local Tools configuration; or
- delete checkout-local metadata inside user repositories.

The project website may be published alongside machine-consumed package metadata on the same static origin, but presentation changes must not weaken package trust, mutate historical release artifacts, or change the package/version contract.

## Breaking changes

Before `1.0.0`, a future minor release such as `0.2.0` may intentionally change a documented command or configuration contract, but the change must be called out in release notes with a migration path when state/configuration is affected.

Patch releases in the `0.1.x` line should remain compatible with this document.
