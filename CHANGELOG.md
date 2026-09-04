# Changelog

All notable user-facing changes to Pantheon Local Tools are recorded here.

The project follows Semantic Versioning for its public command/configuration contract. The repository-root `VERSION` file is canonical; tagged releases use the corresponding `vVERSION` Git tag.

## Unreleased

## 0.1.2 — 2026-09-04

Second patch release after v0.1.1, focused on provider-aware Drupal bootstrap and configuration workflows plus explicit guarded Pantheon Multidev creation while preserving the established 0.1.x safety and compatibility contracts.

### Added

- Added optional Pantheon Tag profile properties in the existing Git-compatible configuration file: `config-strategy` (`full-export` or `overlay-delta`) and a validated project-relative `config-path`.
- Added `pantheon-local config tag profile get/set/unset/list` with focused help, regression coverage, generic examples, and no organization-specific built-ins.
- Added checkout-local `pantheon-local setup [--provider ddev|lando] [--dry-run]` for provider-aware Drupal bootstrap using the checkout's recorded Pantheon environment.
- Added bootstrap status/step/timestamp reporting to checkout-local state and `pantheon-local status`.
- Added `pantheon-local readiness [--provider ddev|lando]` for read-oriented `full-export` Drupal configuration inspection using the recorded Tag profile, configured config path, provider-owned Drush, Config Ignore module-state reporting, and final Git state.
- Added fail-closed `overlay-delta` readiness reporting that validates the configured protected partial path and Git state without invoking a provider/Drush or treating file count/missing YAML as drift.
- Added explicit `pantheon-local config export [--provider ddev|lando] [--yes]` for confirmed `full-export` Drupal configuration mutation with clean-path preflight, Config Ignore runtime awareness, post-export change reporting, and no automatic Git commit/push.
- Added explicit `pantheon-local multidev create SITE.SOURCE NEW_ENV [--provider ddev|lando] [--group NAME] [--dry-run] [--start] [--yes]` for guarded remote Multidev creation, post-create verification, and handoff to the existing transactional local checkout path.

### Changed

- `pantheon-local config list` now reports configured Tag profile properties in addition to the established root/provider and Tag-directory lines.
- `pantheon-local config tag unset TAG` now removes that Tag's optional profile properties so stale strategy/path state is not orphaned after route deletion.
- Debian/Homebrew/release packaging coverage now includes the Tag-profile, Drupal-setup, readiness, explicit config-export, and explicit Multidev-create command modules.
- Drupal setup now composes the existing guarded database-only pull after provider-owned Composer install, then runs `drush updb -y` and `drush cr`, stopping on the first failed step.
- Full-export readiness now verifies the configured profile path against Drupal's runtime config-sync path, reports configuration differences as review states rather than automatically exporting, and fails if inspection itself changes Git-visible source state.
- Readiness now rejects configured directories that escape the Git project root through filesystem links. Overlay-delta reports `Owning validation: unavailable` / `Readiness: unavailable` and exits nonzero until a reliable non-destructive owning validation mechanism exists.
- Config export refuses `overlay-delta`, requires the configured full-export path to be Git-clean before mutation, requires a reliable Config Ignore module-state check, and reports partial local changes if provider-owned `drush config:export` fails after writing files.
- The existing `pantheon-local multidev SITE.ENV` command remains clone-only; missing remote environments are never created implicitly. Remote creation now requires the separate confirmed command, validates Pantheon's naming rules/source/target state before mutation, and preserves the remote environment if later local checkout/start fails.

## 0.1.1 — 2026-08-28

First patch release after v0.1.0, focused on lower-friction onboarding, self-documenting CLI help, and completing the signed APT distribution path.

### Added

- Added `pantheon-local config init` for guided first-run setup using the existing configuration defaults, validation, storage path, and granular setters.
- Added non-interactive `config init --root PATH` and `--provider auto|ddev|lando` options for experienced users and automation.
- Added complete top-level `pantheon-local help` / `pantheon-local --help` output that enumerates the supported public command surface, important options, provider-detection semantics, and representative examples.
- Published the current stable release through the public Homebrew tap at `zevarix/tap`.
- Published a signed Debian/Ubuntu/WSL APT repository on GitHub Pages with dedicated `Signed-By` keyring trust, hosted-Ubuntu validation, and real WSL2 validation.
- Added the public Pantheon Local Tools product homepage at the same GitHub Pages origin used by the signed APT repository.
- Added a one-command Debian/Ubuntu/WSL APT bootstrap that verifies the canonical archive fingerprint, configures the scoped keyring/source, refreshes APT, and installs the package.

### Changed

- Hardened APT publication around immutable release assets, reduced signing-subkey material, explicit rotation boundaries, deterministic repository assembly, and public-client validation.
- Scoped the third-party APT source to the published architecture-independent index so clean installs do not emit an unsupported host-architecture warning.
- Refreshed repository documentation after the first public release so the README acts as a concise project front door and deep implementation/release details remain in focused docs.
- Generalized maintainer release and packaging documentation for future releases instead of leaving first-release-only instructions in durable runbooks.
- Simplified the normal signed-APT onboarding path from several manual copy/paste blocks to one reviewed bootstrap command while retaining the full manual trust procedure.
- Kept moving-branch APT installer completion guidance compatible with the package version actually published as stable.
- Added regression coverage so public commands/options cannot silently disappear from in-tool help.

## 0.1.0 — 2026-08-27

First public release of Pantheon Local Tools.

### Added

- `pantheon-local config` with Git-compatible user configuration and XDG-aware storage.
- User-defined Pantheon Tag-to-directory routing.
- DDEV and Lando as provider adapters behind one CLI.
- `pantheon-local multidev SITE.ENV` for cloning an existing Pantheon multidev into an isolated local checkout.
- Transactional multidev creation using a temporary sibling checkout and no-overwrite finalization.
- Explicit `--dry-run`, `--group`, `--provider`, and opt-in `--start` behavior.
- `pantheon-local status` for local/read-only checkout, Git, provider, runtime URL, and data-provenance inspection.
- Provider-authoritative runtime URL discovery without assuming `lndo.site` or `ddev.site`.
- `pantheon-local pull ENV` with explicit Pantheon source selection and provider-owned authentication.
- Database-only and files-only pull selection.
- Independent database/files provenance recording after successful pulls.
- Git-integrity guards that reject provenance recording if a data pull changes `HEAD` or tracked content.
- `pantheon-local version` and `pantheon-local --version` backed by the canonical `VERSION` file.
- Portable clone installer that does not edit shell startup files and refuses to overwrite unrelated commands.

### Provider safety

- Existing `.lando.yml` and `.ddev/config.yaml` remain provider/project authority.
- Checkout isolation writes only minimal local name overrides.
- Existing services, tooling, add-ons, custom hostnames, proxy routes, and Compose definitions are preserved.
- Ambiguous provider detection fails instead of guessing.
- Pantheon Local Tools does not collect or persist Pantheon machine tokens.
- Lando/DDEV data-transfer implementations remain delegated to their supported provider interfaces.

### Distribution prepared

- Architecture-independent Debian package builder (`Architecture: all`).
- Homebrew formula renderer using exact release URL/version/SHA256 inputs.
- Real temporary-tap Homebrew install/test/uninstall coverage on macOS CI.
- Deterministic `git archive | gzip -n` release source-artifact builder.
- `SHA256SUMS` generation for release artifacts.
- Maintainer release procedure covering tag identity, artifacts, GitHub Release, Homebrew tap publication, Debian packaging, and recovery.

### Validation completed

- Required shell syntax, ShellCheck, and integration tests on Ubuntu and macOS.
- Isolated-home clone-installer tests on Ubuntu and macOS.
- Real macOS + Lando multidev clone, isolated runtime start, Pantheon authentication, explicit database/files pull, provider-derived status, and Git-integrity validation.
- Real WSL2 + DDEV Pantheon startup, provider-derived status, full database/files pull, database-only/files-only pulls, provenance, credential separation, and Git-integrity validation.
- Real WSL2 fresh-clone/install/full-suite validation, including native Windows-path rejection, Debian package tests, ShellCheck, shell-startup-file integrity, and clean Git state.
- Real clean-macOS fresh-clone/install/full-suite validation, including isolated Homebrew package smoke and host-state restoration.
- Homebrew formula installation through an actual temporary tap on macOS CI.
- Debian package build/extract/layout/version tests on Ubuntu CI and real WSL2.
- Deterministic release source-artifact reproduction tests on Ubuntu and macOS.
- Public repository audit for private site/account/organization/UUID/path values.

### Known follow-up

- An additional real DDEV checkout against an entitled Pantheon Multidev environment remains tracked in #24. Real Pantheon Multidev behavior is already validated through Lando, and DDEV Multidev isolation/preservation has deterministic regression coverage.
- Native Debian/APT distribution follow-up remains tracked in #9.

See issue #7 for release-publication status and `docs/real-integration-validation.md` for the real-environment procedures.
