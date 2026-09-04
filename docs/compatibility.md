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
pantheon-local config tag profile get TAG PROPERTY
pantheon-local config tag profile set TAG PROPERTY VALUE
pantheon-local config tag profile unset TAG PROPERTY
pantheon-local config tag profile list [TAG]

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

Running `pantheon-local` with no arguments shows the same top-level command reference as `pantheon-local help` / `pantheon-local --help`. Focused help routes such as `pantheon-local config help`, `pantheon-local config init --help`, `pantheon-local config tag profile --help`, `pantheon-local multidev --help`, `pantheon-local setup --help`, `pantheon-local readiness --help`, `pantheon-local pull --help`, and `pantheon-local status --help` are also supported discovery surfaces.

New commands and additive options may be introduced in a compatible `0.1.x` release when they do not change existing command meaning. In particular, adding `pantheon-local setup` does not change `pantheon-local multidev --start`: `--start` continues to mean provider start only.

## Configuration contract

The following user configuration concepts are public:

- `root` — absolute local root for Pantheon checkouts;
- `provider` — `auto`, `ddev`, or `lando`;
- Pantheon Tag-to-directory mappings managed through `config tag`;
- optional Pantheon Tag profile properties managed through `config tag profile`:
  - `config-strategy` — `full-export` or `overlay-delta`;
  - `config-path` — a validated project-relative configuration path.

`pantheon-local config init` is a convenience layer over the same configuration model. With no flags in a terminal, it guides root/provider selection, validates all proposed values, summarizes them, confirms before writing, and uses the normal configuration setters. With `--root` and/or `--provider`, it is non-interactive and changes only values explicitly supplied by the caller. Existing `config get/set/unset/list/path` and `config tag` commands remain first-class granular controls.

Tag profile properties extend an existing Tag route and use the same Git-compatible `[tag "..."]` subsection. A profile setter does not implicitly create a Tag route. Existing directory-only Tag configuration remains valid, and a Tag route does not need a strategy/path unless a later workflow explicitly requires one. Removing a Tag route through `config tag unset TAG` also removes its optional profile properties so stale strategy/path state is not left behind.

The initial strategy vocabulary is deliberately bounded to `full-export` and `overlay-delta`. The configured `config-path` is data, not a built-in path assumption: `config/sync`, `config/site-overrides`, and organization-specific directories are examples only. The `overlay-delta` label does not make a directory a complete export and does not authorize a blanket Drupal config export.

The default configuration location follows XDG conventions as documented by the CLI/README. `PANTHEON_LOCAL_CONFIG` remains the supported complete-path override for automation/testing.

The Git-compatible on-disk representation is intentionally simple, but users should prefer the CLI rather than depending on undocumented internal key names. `docs/configuration.md` documents the public profile concepts and safety boundaries without making internal Git key spelling a machine API.

## Provider contract

DDEV and Lando are the supported local providers for `0.1.x`.

Provider-owned project configuration remains authoritative. Pantheon Local Tools is additive and must not silently replace or strip existing provider services, tooling, add-ons, proxy/custom-hostname configuration, or custom Compose definitions.

When stored configuration uses `provider=auto`, provider selection is based on project configuration after checkout (`.ddev/config.yaml` versus `.lando.yml`), not simply on which provider binaries are installed. Ambiguous detection fails rather than guessing.

`pantheon-local setup` uses provider-owned command surfaces for provider start, Composer, and Drush. Composer is never silently replaced with host Composer when a supported provider owns the checkout runtime. The database refresh remains delegated through the existing provider-specific `pantheon-local pull --database-only` path.

`pantheon-local readiness` also uses provider-owned Drush. Unlike setup, readiness does not start or rebuild the provider; a runtime that cannot execute the required read-oriented Drush commands is an inspection failure rather than an implicit start request.

A provider-specific implementation detail may change in a patch release when the user-visible command contract and safety properties remain the same.

## Drupal setup contract

`pantheon-local setup` is available only for a checkout with PLT checkout-local state containing a valid `pantheon.environment`. That recorded environment is authoritative for the setup database refresh. Setup must not infer an environment from the Git branch or silently fall back to `live`.

The public setup order is:

```text
provider start
→ provider-owned composer install
→ guarded database-only pull from recorded pantheon.environment
→ provider-owned drush updb -y
→ provider-owned drush cr
```

Setup stops at the first failed mutating step. It must not continue to database pull after a failed Composer install, to `updb` after a failed pull, or to cache rebuild after a failed `updb`.

`pantheon-local setup --dry-run` may inspect local prerequisites and print the plan, but must not start/rebuild a provider, execute Composer/Drush, pull data, contact Pantheon through the pull path, or mutate checkout-local bootstrap state.

Setup is a local mutation workflow. It may start/build provider runtime services; Composer may access the network and execute project scripts; the database pull replaces local database data; and Drush may mutate the local database/cache. Setup does not pull files or Git code, export Drupal configuration, push to Pantheon, or rewrite provider-owned base project configuration.

## Drupal readiness contract

`pantheon-local readiness` is a separate read-oriented inspection boundary. It requires a PLT-managed checkout with a recorded `pantheon.tag` that resolves through the existing Git-compatible profile configuration.

For the current `full-export` implementation, both profile values are required:

- `config-strategy=full-export`;
- a valid project-relative `config-path`.

The configured path must exist and must correspond to the Drupal runtime `config-sync` path reported by provider-owned `drush core:status --field=config-sync`. PLT must not silently substitute or assume `config/sync`.

After the path check, readiness uses provider-owned `drush config:status --format=list` to distinguish synchronized configuration from reported active-versus-sync differences. It also attempts enabled-module inspection through Drush to report Config Ignore as `enabled`, `disabled`, or `unavailable`.

Config Ignore detection is advisory. PLT does not duplicate Config Ignore matching semantics, hide reported configuration differences because Config Ignore is enabled, or treat an unavailable module-state query as permission to guess.

Readiness distinguishes an inspection result from an inspection failure:

- synchronized configuration, reported differences, Config Ignore enabled/disabled/unavailable, and a pre-existing modified Git working tree are successful report states and exit `0` when the inspection itself completed reliably;
- incomplete/unsupported profile data, provider/required-Drush failure, runtime path mismatch, or Git-visible changes caused during inspection fail nonzero.

Readiness records no successful-state metadata and performs no configuration export. It must not run `drush config:export`, `drush cex`, or an equivalent write merely because differences are reported.

`overlay-delta` is intentionally unsupported by this initial readiness implementation. Until its separate contract is implemented, the command must fail rather than apply full-export interpretation to a protected partial/delta directory.

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
- keep help/read-only discovery surfaces free of provider startup, authentication, or filesystem/project mutation;
- validate all guided `config init` selections before writing so an invalid later value cannot leave a partial configuration update;
- reject unsupported Tag `config-strategy` values instead of guessing future semantics;
- reject unsafe/escaping Tag `config-path` values rather than treating them as project-relative paths;
- never make setting a Tag profile property implicitly create a Pantheon Tag route;
- never interpret `overlay-delta` as permission to flatten or fully export Drupal configuration into the configured delta path;
- never let `pantheon-local setup` infer its Pantheon database source from Git branch naming or an implicit Live default;
- never run setup `updb`/`cr` after an earlier required step fails;
- never make `multidev --start` silently perform the full Drupal setup pipeline;
- never let `pantheon-local readiness` start/rebuild a provider or automatically export Drupal configuration;
- never let full-export readiness silently substitute a different config path for the configured Tag profile;
- never apply full-export readiness semantics to an `overlay-delta` profile; and
- never report readiness success if the inspection itself changed Git `HEAD` or Git-visible working-tree state.

Safety tightening that converts a previously ambiguous/unsafe case into an explicit failure is considered compatible when documented in release notes.

## Local checkout state

`.git/pantheon-local-tools/state` is local metadata, not application configuration and not a file users should commit.

Its schema is not a general-purpose external API. However, upgrades must preserve/migrate state created by earlier supported versions rather than silently discarding known provenance or checkout identity.

In particular, the legacy `data.source` migration to independent database/files provenance demonstrates the expected upgrade behavior.

Setup may add local troubleshooting keys for bootstrap status, failed/current step, recorded environment/provider, and update timestamp. `pantheon-local status` may display those fields. Their presence does not make checkout-local state a stable machine API or application configuration.

Readiness consumes the recorded Pantheon Tag and provider identity when available but does not add a persistent readiness-result cache. The current Drupal/Git state is inspected fresh on each run.

## Human-readable output

Normal command output is designed for developers and may gain additional labeled fields in patch releases. Existing labels should not be casually renamed or removed within `0.1.x`.

The text output is **not** yet a stable machine-readable API. Scripts that require a formal structured output format should wait for an explicitly documented JSON/porcelain interface rather than parsing incidental spacing.

Exact non-zero numeric exit codes are not part of the `0.1.x` contract; success is exit `0`, failure is nonzero. A successful readiness inspection may still report a review-required state, as described above.

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
