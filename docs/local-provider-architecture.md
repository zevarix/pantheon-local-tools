# Local Provider Architecture

Pantheon Local Tools separates Pantheon operations from the local development environment used to run a project.

The canonical CLI is `pantheon-local`. Commands such as `pantheon-local multidev`, `pantheon-local pull`, and `pantheon-local status` expose one consistent user workflow while delegating environment-specific details to a provider adapter.

## Host environments

The shell tooling targets:

- macOS;
- Linux; and
- Windows through WSL/WSL2.

Native PowerShell and Command Prompt are not initial targets. WSL is treated as a Linux execution environment: commands use Linux paths such as `/home/user/...` or `/mnt/c/...`, not `C:\...` paths.

Portable shell code avoids Bash 4-only features so the same core can run under the older Bash shipped by macOS and modern Bash on Linux/WSL.

## Why providers

Drupal.org currently recommends DDEV for Drupal local development, while many existing Pantheon projects use Lando. Pantheon also documents DDEV integration with its platform. The tool should not require a team to standardize on one local container stack before it can use the Pantheon workflow helpers.

The shared core therefore owns Pantheon concepts. Provider adapters own local-runtime concepts.

## Shared core responsibilities

The core is responsible for:

- parsing a Pantheon `site.environment` target;
- verifying required commands and Terminus authentication before Pantheon operations;
- querying Terminus for authoritative site and environment information;
- reading Pantheon Tags and applying user-configured Tag-to-directory mappings;
- obtaining the authoritative Git connection for an environment;
- choosing and creating the local destination path;
- refusing to overwrite an existing checkout;
- cloning the selected Pantheon environment;
- selecting a provider without guessing when the result is ambiguous;
- recording non-secret local state needed by status output;
- presenting consistent errors and status output.

The core must not assume DDEV or Lando naming, URL, start, rebuild, or data-pull behavior.

## Terminus authentication boundary

Pantheon Local Tools does not own or store Pantheon credentials. Users authenticate Terminus using Pantheon's supported workflow before running commands that query Pantheon.

The tool should preflight Terminus and provide an actionable error when authentication is missing. It must never prompt for, persist, echo, or copy a Pantheon machine token into Pantheon Local Tools configuration.

Pantheon's canonical references are:

- https://docs.pantheon.io/terminus/install
- https://docs.pantheon.io/machine-tokens
- https://docs.pantheon.io/terminus/commands/auth-login

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
2. user configuration (`local.provider`);
3. unambiguous provider configuration found in the project after cloning;
4. otherwise fail and require an explicit choice.

`auto` is a detection mode, not permission to guess.

If both DDEV and Lando configurations exist, or neither can be identified reliably, the command must stop unless the user supplied a provider explicitly or configured a default.

## Git-style local configuration

User configuration lives outside project repositories, by default at:

```text
~/.config/pantheon-local-tools/config
```

The file uses Git's config format and is read/written through Git itself. Users normally manage it through commands such as:

```bash
pantheon-local config set root ~/sites/pantheon
pantheon-local config set provider ddev
pantheon-local config tag set "Client Sites" clients
```

The root directory is configurable. The project does not assume `~/lando`, `~/sites/pantheon`, or any organization-specific directory layout.

Pantheon Tag routing is also user-defined. Pantheon Tags are the authoritative source labels; the mapped local directories are only developer-specific destinations.

## Safety rules

- Never overwrite an existing checkout.
- Never commit machine-specific provider overrides automatically.
- Never embed Pantheon tokens, SSH keys, credentials, or organization-private values.
- Never store executable shell code as user configuration.
- Never start, rebuild, delete, or otherwise mutate a local runtime as a hidden side effect.
- Never perform a Pantheon remote write unless the user explicitly requested an operation that requires it.
- Fail on ambiguous Pantheon Tag routing or provider selection instead of guessing.
- Under WSL, use Linux path semantics and reject native Windows path syntax where it would be unsafe or ambiguous.

## Upstream references

- Drupal local server setup: https://www.drupal.org/docs/develop/local-server-setup
- Pantheon Terminus install/authentication: https://docs.pantheon.io/terminus/install
- Pantheon machine tokens: https://docs.pantheon.io/machine-tokens
- Pantheon `auth:login`: https://docs.pantheon.io/terminus/commands/auth-login
- Pantheon DDEV guide: https://docs.pantheon.io/guides/local-development/ddev
- Pantheon local development guide: https://docs.pantheon.io/guides/local-development
- DDEV configuration overrides: https://ddev.readthedocs.io/en/stable/users/configuration/config/
