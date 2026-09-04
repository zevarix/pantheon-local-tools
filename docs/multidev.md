# Multidev workflows

Pantheon Local Tools keeps **existing-environment checkout** and **remote-environment creation** as separate command contracts.

```bash
pantheon-local multidev SITE.ENV
pantheon-local multidev create SITE.SOURCE NEW_ENV
```

The first command is clone-only and never creates a missing Pantheon environment. The second command is an explicit remote-write operation that creates a new Pantheon Multidev and then hands off to the existing clone-only path.

## Existing Multidev checkout

`pantheon-local multidev SITE.ENV` creates a local checkout for an already-existing Pantheon Multidev without changing that environment on Pantheon.

Supported options remain:

```text
--provider ddev|lando
--group NAME
--dry-run
--start
```

A missing `SITE.ENV` never implies permission to create it. Use the distinct `multidev create` command when a remote environment should be created deliberately.

## Explicit remote Multidev creation

Use:

```bash
pantheon-local multidev create SITE.SOURCE NEW_ENV \
  [--provider ddev|lando] \
  [--group NAME] \
  [--dry-run] \
  [--start] \
  [--yes]
```

`SITE.SOURCE` is an existing Pantheon source environment. `NEW_ENV` is the new Multidev name.

Pantheon's documented `terminus multidev:create <site>.<env> <multidev>` behavior creates the Multidev and, by default, clones the database and files from the source environment. PLT preserves that default and does not add separate content-clone flags in this initial command.

### New-environment naming

PLT validates Pantheon's documented Multidev naming constraints before any remote write. `NEW_ENV` must:

- be lowercase;
- contain at most 11 characters;
- start with a letter or number;
- contain only lowercase ASCII letters, numbers, and dashes;
- not use Pantheon's reserved environment names: `master`, `settings`, `team`, `support`, `multidev`, `debug`, `files`, `tags`, or `billing`.

This is intentionally stricter than the parser used for an already-existing `SITE.ENV`: PLT is validating a new Pantheon environment name, not normalizing it or relying on a later remote failure.

### Creation preflight

Before mutation, PLT:

1. validates `SITE.SOURCE`, `NEW_ENV`, provider/group options, and the local PLT root/provider configuration it can establish without a checkout;
2. verifies Terminus authentication with `terminus auth:whoami`;
3. reads the site's environments through `terminus env:list`;
4. requires the source environment to exist;
5. requires the target environment not to exist;
6. prints the remote-create/local-handoff plan;
7. requires interactive confirmation unless `--yes` was supplied.

PLT does not construct Pantheon UUIDs, Git URLs, or environment-existence assumptions during this preflight.

### Remote mutation and verification

After confirmation, PLT invokes the documented Terminus creation command with Terminus confirmation already acknowledged by PLT:

```text
terminus multidev:create SITE.SOURCE NEW_ENV --yes
```

Current Terminus waits for a newly created Multidev to become fully awake before returning. PLT still performs a separate read-back through `terminus env:list` and requires the new environment to appear before local checkout begins.

If Terminus returns failure, PLT treats remote state as potentially partial or uncertain. It does **not** retry automatically and does **not** delete anything. Verify Pantheon state before issuing another create command.

If Terminus returns success but the verification list is unavailable or does not contain the new environment, PLT also stops before local checkout. It reports the remote state as uncertain rather than attempting a second create blindly.

### Handoff to the existing checkout path

After successful remote verification, PLT invokes the same existing Multidev checkout implementation used by:

```bash
pantheon-local multidev SITE.NEW_ENV
```

The create command does not duplicate Git URL resolution, Pantheon Tag routing, destination calculation, transactional cloning, provider validation/configuration, checkout-local state, runtime URL discovery, or provider-start behavior.

`--provider`, `--group`, and `--start` are passed through to that existing path.

If remote creation succeeds but local checkout or provider start fails, the remote Multidev is **preserved**. PLT prints a retry command using the existing clone-only surface. It never rolls back by deleting the remote environment.

## Creation dry-run

`pantheon-local multidev create ... --dry-run` performs only read-oriented validation/planning:

- local CLI/config validation;
- Terminus authentication;
- source/target existence checks;
- plan reporting.

It does not:

- call `terminus multidev:create`;
- clone Git;
- create a local checkout directory;
- write provider overrides;
- start DDEV/Lando.

`--start` cannot be combined with `--dry-run`.

Dry-run identifies the local handoff options rather than pretending the not-yet-created target has a resolvable Pantheon Git endpoint. The existing clone path performs the authoritative remote Tag/Git/destination checks only after creation has been verified.

## Creation confirmation and automation

A real `multidev create` is an explicit remote Pantheon mutation, but PLT still confirms immediately before that mutation in interactive use.

For non-interactive use, supply:

```bash
pantheon-local multidev create example-site.live feature1 --yes
```

`--yes` acknowledges only the PLT creation confirmation. It does not bypass naming checks, authentication, source existence, target absence, local config preflight, post-create verification, or existing checkout safety.

## Pantheon contracts

The Multidev workflows rely on documented Terminus interfaces:

- `terminus auth:whoami` verifies that Terminus has an authenticated identity.
- `terminus env:list <site>` provides the source/target environment existence list used by remote creation.
- `terminus multidev:create <site>.<env> <multidev>` performs the explicit remote creation.
- `terminus site:info <site> --field=organization` resolves the site's organization when Pantheon Tag routing is configured for local checkout.
- `terminus tag:list <site> <org> --format=list` returns the Pantheon Tags for local routing.
- `terminus connection:info <site>.<env> --field=git_url` supplies the Git endpoint used by the existing checkout path.

Neither workflow constructs a Pantheon Git URL from UUID assumptions.

## Tag routing

Pantheon Tags are remote source labels. Local directories are user-defined destinations.

When the user has no Tag mappings, Multidev checkouts live directly below:

```text
<root>/multidev/
```

When mappings exist, exactly one configured Tag must match the site's Pantheon Tags. A zero-match or multi-match result stops local checkout so that PLT never guesses where a checkout belongs.

For `multidev create`, Tag routing is intentionally resolved by the existing checkout path **after** remote creation. If routing prevents local checkout, the remote environment remains available and the reported clone-only retry command can be used after local configuration is corrected.

## Local names

The local name is derived from `<site>-<env>`, normalized to lowercase DNS-safe characters, and limited to 63 characters. Pantheon site and environment names are preserved unchanged for remote operations; only the derived local name is normalized.

## Transactional local creation

The existing checkout command refuses to overwrite an existing final destination.

For a real clone, it creates a temporary sibling checkout, validates/configures the selected provider there, records local state, and only then moves the completed checkout into the final destination. If cloning or provider configuration fails, the temporary checkout is removed rather than leaving a partial final destination.

An explicitly requested provider start happens only after the final checkout exists. If a provider start fails, the completed checkout is retained for troubleshooting. When that checkout followed a successful remote `multidev create`, the remote environment is retained as well.

## Provider behavior

Provider-owned project configuration remains authoritative. Pantheon Local Tools adds only the minimum checkout-local name override required to isolate the cloned environment.

It does not rewrite base provider configuration, service definitions, proxy definitions, custom tooling, add-ons, custom Compose files, or provider-owned URL/Drush settings.

### Lando

The project must contain `.lando.yml`.

Pantheon Local Tools writes `.lando.local.yml` containing only the isolated local app name and adds it to `.git/info/exclude`. The shared `.gitignore` is not modified.

`--start` runs `lando start`. PLT does not automatically run `lando rebuild`.

### DDEV

The project must contain `.ddev/config.yaml`.

Pantheon Local Tools writes `.ddev/config.local.yaml` with the isolated local project name and records the generated path in `.git/info/exclude` without modifying the project `.gitignore`.

Existing additional hostnames, add-ons, and `docker-compose.*.yaml` services remain provider-owned and are not rewritten.

`--start` runs `ddev start`.

## Local URL metadata

Pantheon Local Tools does not construct a URL from the local name plus an assumed provider suffix.

After checkout creation it makes a best-effort, read-only provider inspection:

- Lando application URLs are read through `lando info` when available.
- DDEV's primary URL is read through `ddev describe -j` when available.

If the provider can report a URL, it is recorded as local metadata under `.git/pantheon-local-tools/state`. If the provider cannot report one, checkout creation still succeeds and no URL is invented.

A successful explicit `--start` performs URL discovery again after the provider starts and refreshes the recorded URL when available.

## Existing-checkout dry-run

`pantheon-local multidev SITE.ENV --dry-run` performs the existing read-only Terminus lookups and prints the resolved checkout plan without creating directories, cloning Git, writing provider configuration, or querying a local provider runtime.

Because no checkout exists yet, dry-run intentionally reports the local URL as provider-runtime information that will become available only after checkout/provider inspection. It never guesses `lndo.site`, `ddev.site`, or another domain.

If provider selection is `auto`, dry-run cannot inspect the future checkout. Configure a provider or pass `--provider ddev|lando` for a fully resolved provider choice.

## Safety / non-goals

The clone-only `pantheon-local multidev SITE.ENV` command does not:

- create or delete Pantheon Multidev environments;
- change Pantheon connection modes;
- push code to Pantheon;
- pull databases or files;
- store Pantheon machine tokens;
- overwrite existing local checkouts;
- create a project's base DDEV/Lando configuration when none exists;
- replace provider-owned hostname/proxy configuration.

The explicit `multidev create` command adds exactly one remote mutation: creating the named Multidev from the named source. It does **not**:

- delete or automatically roll back a remote Multidev;
- create a remote environment because an ordinary clone target is missing;
- run Composer, database bootstrap, `drush updb`, cache rebuild, readiness, or config export;
- commit or push project code;
- change the semantics of `--start`.

## Upstream references

- Pantheon `multidev:create`: https://docs.pantheon.io/terminus/commands/multidev-create
- Pantheon Multidev creation/naming: https://docs.pantheon.io/guides/multidev/create-multidev
- Pantheon Multidev FAQ: https://docs.pantheon.io/guides/multidev/multidev-faq
- Pantheon `env:list`: https://docs.pantheon.io/terminus/commands/env-list
- Pantheon `connection:info`: https://docs.pantheon.io/terminus/commands/connection-info
- Pantheon `site:info`: https://docs.pantheon.io/terminus/commands/site-info
- Pantheon `tag:list`: https://docs.pantheon.io/terminus/commands/tag-list
- Pantheon Terminus install: https://docs.pantheon.io/terminus/install
- Pantheon machine tokens: https://docs.pantheon.io/machine-tokens
- DDEV configuration overrides: https://docs.ddev.com/en/stable/users/configuration/config/
- DDEV `describe`: https://docs.ddev.com/en/stable/users/usage/commands/
- Lando override files: https://docs.lando.dev/landofile/index.html
- Lando `info`: https://docs.lando.dev/cli/info.html
- Lando Pantheon configuration: https://docs.lando.dev/plugins/pantheon/config.html
