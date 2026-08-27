# Changelog

All notable user-facing changes to Pantheon Local Tools are recorded here.

The project follows Semantic Versioning for its public command/configuration contract. The repository-root `VERSION` file is canonical; tagged releases use the corresponding `vVERSION` Git tag.

## 0.1.0 — Unreleased

The first public release is still undergoing real-host/provider validation. Until `v0.1.0` is tagged, install from a clone only if you are comfortable using pre-release software.

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
- Homebrew formula installation through an actual temporary tap on macOS CI.
- Debian package build/extract/layout/version tests on Ubuntu CI.
- Deterministic release source-artifact reproduction tests on Ubuntu and macOS.
- Public repository audit for private site/account/organization/UUID/path values.

### Still required before v0.1.0

- Real DDEV + Pantheon multidev/start/pull/status validation (#17).
- Real WSL2 fresh-clone/install/test validation (#18).
- Real clean macOS fresh-clone/install/test validation (#18).
- Final release-version commit/tag and immutable release artifact checksum verification.
- Publication and clean-install verification of the real `zevarix/tap` Homebrew formula.
- Released package-manager upgrade behavior.

See issue #7 for the authoritative release-readiness tracker and `docs/real-integration-validation.md` for the real-environment procedures.
