# Local Provider Architecture

Pantheon Local Tools separates Pantheon operations from the local development environment used to run a project.

The goal is for commands such as `pantheon-multidev`, `pantheon-pull`, and `pantheon-status` to expose one consistent user workflow while delegating environment-specific details to a provider adapter.

## Why providers

Drupal.org currently recommends DDEV for Drupal local development, while many existing Pantheon projects use Lando. Pantheon also documents DDEV integration with its platform. The tool should not require a team to standardize on one local container stack before it can use the Pantheon workflow helpers.

The shared core therefore owns Pantheon concepts. Provider adapters own local-runtime concepts.

## Shared core responsibilities

The core is responsible for:

- parsing a Pantheon `site.environment` target;
- querying Terminus for authoritative site and environment information;
- reading Pantheon Tags and applying user-configured Tag-to-directory mappings;
- obtaining the authoritative Git connection for an environment;
- choosing and creating the local destination path;
- refusing to overwrite an existing checkout;
- cloning the selected Pantheon environment;
- selecting a provider without guessing when the result is ambiguous;
- recording non-secret local state needed by `pantheon-status`;
- presenting consistent errors and status output.

The core must not assume DDEV or Lando naming, URL, start, rebuild, or data-pull behavior.

## Provider responsibilities

A provider adapter is responsible for local behavior such as:

- detecting whether its project configuration is present;
- creating local-only configuration for an isolated checkout;
- calculating or discovering the local project name and URL;
- starting or restarting the local environment when explicitly requested;
- pulling/importing database and files through the provider's supported workflow;
- reporting provider-specific status.

The first providers are:

### DDEV

DDEV projects use `.ddev/config.yaml` and may use local-only `config.*.yaml` overrides such as `.ddev/config.local.yaml`.

Pantheon documents a DDEV provider integration that supports `ddev pull pantheon`. Where the project is configured for that integration, the DDEV adapter should prefer the documented DDEV workflow rather than reimplementing it.

### Lando

Lando projects use `.lando.yml`. Checkout-specific settings can be placed in `.lando.local.yml` and kept outside version control.

The Lando adapter should preserve the project's existing recipe and services while applying only the minimum local overrides needed for an isolated checkout.

## Provider selection

Provider selection follows this precedence:

1. explicit command option (`--provider ddev` or `--provider lando`);
2. user configuration (`PANTHEON_LOCAL_PROVIDER`);
3. unambiguous provider configuration found in the project after cloning;
4. otherwise fail and require an explicit choice.

`auto` is a detection mode, not permission to guess.

If both DDEV and Lando configurations exist, or neither can be identified reliably, the command must stop unless the user supplied a provider explicitly or configured a default.

## Local configuration

User configuration lives outside project repositories, by default at:

```text
~/.config/pantheon-local-tools/config
```

The root directory is configurable. The project does not assume `~/lando`, `~/sites/pantheon`, or any organization-specific directory layout.

Pantheon Tag routing is also user-defined. Pantheon Tags are the authoritative source labels; the mapped local directories are only developer-specific destinations.

## Safety rules

- Never overwrite an existing checkout.
- Never commit machine-specific provider overrides automatically.
- Never embed Pantheon tokens, SSH keys, credentials, or organization-private values.
- Never start, rebuild, delete, or otherwise mutate a local runtime as a hidden side effect.
- Never perform a Pantheon remote write unless the user explicitly requested an operation that requires it.
- Fail on ambiguous Tag routing or provider selection instead of guessing.

## Upstream references

- Drupal local server setup: https://www.drupal.org/docs/develop/local-server-setup
- Pantheon DDEV guide: https://docs.pantheon.io/guides/local-development/ddev
- Pantheon local development guide: https://docs.pantheon.io/guides/local-development
- DDEV configuration overrides: https://ddev.readthedocs.io/en/stable/users/configuration/config/
