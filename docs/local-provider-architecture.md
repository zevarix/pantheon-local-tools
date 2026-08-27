# Local Provider Architecture

Pantheon Local Tools separates Pantheon operations from the local development environment used to run a project.

The goal is for commands such as `pantheon-local multidev`, `pantheon-local pull`, and `pantheon-local status` to expose one consistent user workflow while delegating environment-specific details to a provider adapter.

The initial release is being validated against Drupal projects. The shared Pantheon/Terminus core should remain framework-neutral where doing so does not weaken validation or safety.

## Why providers

Drupal.org recommends DDEV for Drupal local development, while many existing Pantheon projects use Lando. The tool should not require a team to standardize on one local container stack before it can use the shared Pantheon workflow helpers.

The shared core therefore owns Pantheon concepts. Provider adapters own local-runtime concepts.

## Shared core responsibilities

The core is responsible for:

- parsing a Pantheon `site.environment` target;
- checking Terminus authentication before Pantheon operations;
- querying Terminus for authoritative site and environment information;
- reading Pantheon Tags and applying user-configured Tag-to-directory mappings;
- obtaining the authoritative Git connection for an environment;
- choosing and creating the local destination path;
- refusing to overwrite an existing checkout;
- selecting a provider without guessing when the result is ambiguous;
- recording non-secret local state needed by later status commands; and
- presenting consistent errors and status output.

The core must not assume DDEV or Lando naming, start, rebuild, or data-pull behavior.

## Provider responsibilities

A provider adapter is responsible for local behavior such as:

- detecting whether its project configuration is present;
- creating local-only configuration for an isolated checkout;
- calculating the local project name and URL;
- starting the local environment when explicitly requested;
- eventually importing database/files through the provider's supported workflow; and
- reporting provider-specific status.

The first providers are DDEV and Lando.

### DDEV

DDEV projects use `.ddev/config.yaml` and may use local-only `config.*.yaml` overrides such as `.ddev/config.local.yaml`.

The current multidev implementation requires an existing `.ddev/config.yaml`; it does not synthesize the project's base DDEV configuration. It creates only the isolated local name override.

Pantheon documents DDEV provider integration that supports `ddev pull pantheon`. The later `pull` command should prefer supported provider integration when the project is configured for it rather than reimplementing provider behavior unnecessarily.

### Lando

Lando projects use `.lando.yml`. Checkout-specific settings can be placed in `.lando.local.yml`, which Lando loads after the shared Landofile.

The current multidev implementation requires an existing `.lando.yml` and creates only the minimum local override needed for an isolated checkout. For Drupal sites it also corrects `DRUSH_OPTIONS_URI` to the isolated local app URL.

## Provider selection

Provider selection follows this precedence:

1. explicit command option (`--provider ddev` or `--provider lando`);
2. user configuration (`pantheon-local config set provider ...`);
3. unambiguous provider configuration found in the cloned project when the configured value is `auto`;
4. otherwise fail and require an explicit choice.

`auto` is a detection mode, not permission to guess.

If both DDEV and Lando configurations exist, or neither can be identified reliably, the command stops unless the user supplied or configured a provider.

A dry-run cannot inspect a future checkout, so `provider=auto` requires `--provider` for a fully resolved multidev dry-run.

## Local configuration

User configuration lives outside project repositories, by default at:

```text
~/.config/pantheon-local-tools/config
```

The file uses Git-compatible configuration data and is normally managed through `pantheon-local config` commands instead of manual editing.

The root directory is configurable. The project does not assume `~/lando`, `~/sites/pantheon`, or any organization-specific directory layout.

Pantheon Tag routing is also user-defined. Pantheon Tags are the authoritative source labels; the mapped local directories are only developer-specific destinations.

## Safety rules

- Never overwrite an existing checkout.
- Build a new multidev checkout in a temporary sibling path and finalize it only after provider configuration succeeds.
- Never commit machine-specific provider overrides automatically.
- Never embed Pantheon tokens, SSH keys, credentials, or organization-private values.
- Never start, rebuild, delete, or otherwise mutate a local runtime as a hidden side effect.
- Never perform a Pantheon remote write unless the user explicitly requested an operation that requires it.
- Fail on ambiguous Tag routing or provider selection instead of guessing.
- Keep organization-specific Pantheon Tags and directory mappings out of the repository.

## Upstream references

- Drupal local server setup: https://www.drupal.org/docs/develop/local-server-setup
- Pantheon DDEV guide: https://docs.pantheon.io/guides/local-development/ddev
- Pantheon local development guide: https://docs.pantheon.io/guides/local-development
- Pantheon Terminus commands: https://docs.pantheon.io/terminus/commands
- DDEV configuration overrides: https://ddev.readthedocs.io/en/stable/users/configuration/config/
- Lando Landofile override files: https://docs.lando.dev/landofile/index.html
