# Multidev Checkout Workflow

`pantheon-local multidev SITE.ENV` creates a local checkout for an existing Pantheon multidev environment without changing that environment on Pantheon.

## Pantheon contracts

The implementation relies on documented Terminus interfaces:

- `terminus auth:whoami` verifies that Terminus has an authenticated identity.
- `terminus site:info <site> --field=organization` resolves the site's organization when Pantheon Tag routing is configured.
- `terminus tag:list <site> <org> --format=list` returns the Pantheon Tags for routing.
- `terminus site:info <site> --field=framework` supplies framework metadata used only where a provider needs a framework-specific local override.
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

### Lando

The project must contain `.lando.yml`.

Pantheon Local Tools writes `.lando.local.yml` with an isolated local app name. For Drupal framework values, it also overrides `DRUSH_OPTIONS_URI` so a committed project-level URI cannot point Drush at a different local Lando app name.

The generated override is added to `.git/info/exclude`. The shared `.gitignore` is not modified.

`--start` runs `lando start`. The tool does not automatically run `lando rebuild`.

### DDEV

The project must contain `.ddev/config.yaml`.

Pantheon Local Tools writes `.ddev/config.local.yaml` with the isolated local project name. DDEV already treats local config overrides as local-only, and the tool additionally records the generated path in `.git/info/exclude` without modifying the project `.gitignore`.

`--start` runs `ddev start`.

## Dry-run

`--dry-run` performs the read-only Terminus lookups and prints the resolved plan without creating directories, cloning Git, or writing provider configuration.

If provider selection is `auto`, dry-run cannot inspect the future checkout. Configure a provider or pass `--provider ddev|lando` for a fully resolved dry-run.

## Non-goals

The multidev command does not:

- create or delete Pantheon multidev environments;
- change Pantheon connection modes;
- push code to Pantheon;
- pull databases or files;
- store Pantheon machine tokens;
- overwrite existing local checkouts; or
- create a project's base DDEV/Lando configuration when none exists.

## Upstream references

- Pantheon `connection:info`: https://docs.pantheon.io/terminus/commands/connection-info
- Pantheon `site:info`: https://docs.pantheon.io/terminus/commands/site-info
- Pantheon `tag:list`: https://docs.pantheon.io/terminus/commands/tag-list
- Pantheon Terminus install: https://docs.pantheon.io/terminus/install
- Pantheon machine tokens: https://docs.pantheon.io/machine-tokens
- DDEV configuration overrides: https://ddev.readthedocs.io/en/stable/users/configuration/config/
- Lando override files: https://docs.lando.dev/landofile/index.html
