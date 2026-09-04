# Drupal checkout setup

`pantheon-local setup` prepares an existing Pantheon Local Tools-managed Drupal checkout for local development without changing the meaning of `pantheon-local multidev --start`.

The command is intentionally checkout-local. Run it from the checkout root or any subdirectory after `pantheon-local multidev SITE.ENV` has created the checkout and recorded its Pantheon identity.

## Command

```bash
pantheon-local setup [--provider ddev|lando] [--dry-run]
```

Examples:

```bash
pantheon-local setup --dry-run
pantheon-local setup
pantheon-local setup --provider lando
```

`--provider` overrides provider selection for this run only. It does not rewrite provider project configuration or global PLT configuration.

## Required pipeline

A mutating setup run executes exactly these phases in order:

```text
provider start
→ provider-owned Composer install
→ guarded database-only pull from the checkout's recorded Pantheon environment
→ provider-owned drush updb -y
→ provider-owned drush cr
```

For Lando this maps to:

```text
lando start
lando composer install
pantheon-local pull RECORDED_ENV --database-only --provider lando
lando drush updb -y
lando drush cr
```

For DDEV this maps to:

```text
ddev start
ddev composer install
pantheon-local pull RECORDED_ENV --database-only --provider ddev
ddev drush updb -y
ddev drush cr
```

The delegated pull remains the existing PLT pull implementation, so provider-owned Pantheon authentication, database provenance, and the Git `HEAD`/tracked-content integrity check stay centralized rather than being reimplemented in setup.

## Pantheon environment authority

Setup requires `.git/pantheon-local-tools/state` and reads `pantheon.environment` from that checkout-local state.

It does **not**:

- infer the Pantheon environment from the current Git branch;
- silently fall back to `live`;
- query Pantheon to guess an environment; or
- accept an unrecorded environment merely because provider configuration exists.

This keeps a checkout cloned from (for example) `SITE.phase1` tied to `phase1` even if the local Git branch is renamed later.

## Preflight

Before any provider command runs, setup verifies:

- it is inside a Git checkout;
- PLT checkout-local state exists;
- a valid recorded `pantheon.environment` exists;
- provider selection is unambiguous or explicitly overridden;
- the selected provider's project configuration exists;
- `composer.json` exists at the checkout root;
- the PLT pull module is installed; and
- DDEV checkouts contain `.ddev/providers/pantheon.yaml` before setup can reach the destructive local pull.

These checks keep known local failures from starting/rebuilding a provider unnecessarily.

## Dry-run

`pantheon-local setup --dry-run` performs the local preflight and prints the exact planned environment, provider, database source, and five-step pipeline.

Dry-run does not:

- start a provider;
- run Composer or Composer scripts;
- run Drush;
- pull a database;
- contact Pantheon through the pull path; or
- update checkout-local bootstrap state.

## Mutation and safety boundaries

Setup is explicitly mutating **locally**:

- provider start may build/rebuild local runtime containers;
- `composer install` can access the network and execute project-defined Composer scripts;
- the database-only pull replaces the local database from the recorded Pantheon environment;
- `drush updb -y` applies pending database updates; and
- `drush cr` rebuilds Drupal caches.

Setup does not pull files. It does not pull or replace Git code. It does not automatically export Drupal configuration. It does not push code, config, files, or database data to Pantheon.

Provider-owned `.lando.yml`, `.ddev/config.yaml`, services, add-ons, Compose extensions, and tooling remain authoritative. Setup invokes provider commands; it does not rewrite those base definitions.

## Failure and retry behavior

Before each mutating phase, setup records the active step as `in-progress` in checkout-local PLT state. If the phase fails, setup records `failed` plus the exact failed step and stops immediately.

The recorded step names are:

- `provider-start`;
- `composer-install`;
- `database-pull`;
- `drush-updb`;
- `drush-cr`; and
- `complete` after success.

No later phase runs after a failure. In particular:

- a failed provider start prevents Composer;
- a failed Composer install prevents database pull;
- a failed database pull prevents both Drush commands;
- a failed `updb` prevents cache rebuild.

Fix the reported problem and rerun `pantheon-local setup`. The command deliberately starts from phase 1 again rather than trying to infer that a previously successful mutating phase is safe to skip.

## Status and provenance

Successful database provenance continues to be owned by `pantheon-local pull`, which records `data.database-source` only after provider success and Git-integrity verification.

Setup additionally records checkout-local bootstrap metadata:

```text
bootstrap.status
bootstrap.step
bootstrap.environment
bootstrap.provider
bootstrap.updated-at
```

`pantheon-local status` reports the latest bootstrap status, step, and timestamp. These values are local troubleshooting metadata under `.git/pantheon-local-tools/state`; they are not application configuration and must not be committed.

## Provider references

PLT follows the providers' supported command surfaces rather than shelling into containers with hand-built Docker commands:

- Lando start / Drupal tooling: https://docs.lando.dev/getting-started/first-app.html and https://docs.lando.dev/plugins/drupal/v/dev/tooling.html
- DDEV commands (`start`, `composer`, `drush`): https://docs.ddev.com/en/stable/users/usage/commands/
- DDEV Pantheon provider/pull integration: https://docs.ddev.com/en/stable/users/providers/pantheon/

The exact provider implementation may evolve while the public PLT setup order and safety contract remain stable.
