# Multidev Checkout Workflow

`pantheon-local multidev SITE.ENV` creates a local checkout for an existing Pantheon multidev environment without changing that environment on Pantheon.

## Pantheon contracts

The implementation relies on documented Terminus interfaces:

- `terminus auth:whoami` verifies that Terminus has an authenticated identity.
- `terminus site:info <site> --field=organization` resolves the site's organization when Pantheon Tag routing is configured.
- `terminus tag:list <site> <org> --format=list` returns the Pantheon Tags for routing.
- `terminus connection:info <site>.<env> --field=git_url` supplies the Git endpoint used for cloning.

The command never constructs a Pantheon Git URL from UUID assumptions.

## Tag routing

Pantheon Tags are the remote source labels. Local directories are user-defined destinations.

When the user has no Tag mappings, multidev checkouts live directly below:

```text
<root>/multidev/
```

When mappings exist, exactly one configured Tag must match the site's Pantheon Tags. A zero-match or multi-match result stops the command so that it never guesses where a checkout belongs.

## Local names

The local name is derived from `<site>-<env>`, normalized to lowercase DNS-safe characters, and limited to 63 characters. Pantheon site and environment names are preserved unchanged for all remote operations; only the derived local name is normalized.

## Transactional local creation

The command refuses to overwrite an existing final destination.

For a real clone, it creates a temporary sibling checkout, validates/configures the selected provider there, records local state, and only then moves the completed checkout into the final destination. If cloning or provider configuration fails, the temporary checkout is removed rather than leaving a partial final destination.

An explicitly requested provider start happens only after the final checkout exists. If a provider start fails, the completed checkout is retained for troubleshooting.

## Provider behavior

Provider-owned project configuration remains authoritative. Pantheon Local Tools adds only the minimum checkout-local name override required to isolate the cloned environment.

It does not rewrite base provider configuration, service definitions, proxy definitions, custom tooling, add-ons, custom Compose files, or provider-owned URL/Drush settings. This preserves project extras such as phpMyAdmin, Redis, Solr, MailHog, custom tooling, and additional services.

### Lando

The project must contain `.lando.yml`.

Pantheon Local Tools writes `.lando.local.yml` containing only the isolated local app name. The Pantheon recipe already derives its normal Drush URI from the provider proxy URL; explicit project-owned Drush/proxy configuration is left untouched rather than replaced with a hard-coded `lndo.site` value.

The generated override is added to `.git/info/exclude`. The shared `.gitignore` is not modified.

`--start` runs `lando start`. The tool does not automatically run `lando rebuild`.

### DDEV

The project must contain `.ddev/config.yaml`.

Pantheon Local Tools writes `.ddev/config.local.yaml` with the isolated local project name. DDEV already treats local config overrides as local-only, and the tool additionally records the generated path in `.git/info/exclude` without modifying the project `.gitignore`.

Existing additional hostnames, add-ons, and `docker-compose.*.yaml` services remain provider-owned and are not rewritten.

`--start` runs `ddev start`.

## Local URL metadata

Pantheon Local Tools does not construct a URL from the local name plus an assumed provider suffix.

After checkout creation it makes a best-effort, read-only provider inspection:

- Lando application URLs are read through `lando info` when available.
- DDEV's primary URL is read through `ddev describe -j` when available.

If the provider can report a URL, it is recorded as local metadata under `.git/pantheon-local-tools/state`. If the provider is not installed, is stopped in a way that prevents inspection, or otherwise cannot report a URL, checkout creation still succeeds and no URL is invented. `pantheon-local status` will try the same read-only provider discovery later and fall back to recorded metadata when appropriate.

A successful explicit `--start` performs URL discovery again after the provider starts and refreshes the recorded URL when available.

## Dry-run

`--dry-run` performs the read-only Terminus lookups and prints the resolved plan without creating directories, cloning Git, writing provider configuration, or querying a local provider runtime.

Because no checkout exists yet, dry-run intentionally reports the local URL as provider-runtime information that will become available only after checkout/provider inspection. It never guesses `lndo.site`, `ddev.site`, or another domain.

If provider selection is `auto`, dry-run cannot inspect the future checkout. Configure a provider or pass `--provider ddev|lando` for a fully resolved provider choice.

## Non-goals

The multidev command does not:

- create or delete Pantheon multidev environments;
- change Pantheon connection modes;
- push code to Pantheon;
- pull databases or files;
- store Pantheon machine tokens;
- overwrite existing local checkouts;
- create a project's base DDEV/Lando configuration when none exists; or
- replace provider-owned hostname/proxy configuration.

## Upstream references

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
