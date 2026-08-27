# Local Provider Architecture

Pantheon Local Tools separates Pantheon operations from the local development environment used to run a project.

Commands such as `pantheon-local multidev`, `pantheon-local pull`, and `pantheon-local status` expose one consistent user workflow while delegating environment-specific behavior to provider adapters.

The initial release is being validated against Drupal projects. The shared Pantheon/Terminus core should remain framework-neutral where doing so does not weaken validation or safety.

## Why providers

Drupal.org recommends DDEV for Drupal local development, while many existing Pantheon projects use Lando. The tool should not require a team to standardize on one local container stack before it can use the shared Pantheon workflow helpers.

The shared core therefore owns Pantheon concepts. Provider adapters own local-runtime concepts.

## Shared core responsibilities

The core is responsible for:

- parsing and validating Pantheon site/environment identifiers;
- checking Terminus authentication when a command directly queries Pantheon;
- querying Terminus for authoritative site and environment information;
- reading Pantheon Tags and applying user-configured Tag-to-directory mappings;
- obtaining the authoritative Git connection for an environment;
- choosing and creating the local destination path;
- refusing to overwrite an existing checkout;
- selecting a provider without guessing when the result is ambiguous;
- recording non-secret local state and component-specific data provenance; and
- presenting consistent errors and status output.

The shared layer must not reimplement DDEV or Lando database/files synchronization when the provider already supplies a supported Pantheon workflow.

## Provider responsibilities

A provider adapter is responsible for local behavior such as:

- detecting whether its project configuration is present;
- creating local-only configuration for an isolated checkout;
- calculating the local project name and URL;
- starting the local environment when explicitly requested;
- importing database/files through the provider's supported Pantheon workflow; and
- reporting provider-specific status.

The first providers are DDEV and Lando.

### DDEV

DDEV projects use `.ddev/config.yaml` and may use local-only `config.*.yaml` overrides such as `.ddev/config.local.yaml`.

The multidev workflow requires an existing `.ddev/config.yaml`; it does not synthesize the project's base DDEV configuration. It creates only the isolated local name override.

For data pulls, DDEV's Pantheon provider is the implementation boundary. `pantheon-local pull ENV` delegates to `ddev pull pantheon` and supplies the requested environment as a one-time `DDEV_PANTHEON_ENVIRONMENT` override. When Pantheon Local Tools has a recorded site name, it also supplies `DDEV_PANTHEON_SITE` for an explicit site/environment binding. The project configuration is not rewritten.

Component selectors map directly to DDEV's supported skip flags:

- default: database + files;
- `--database-only`: add `--skip-files`;
- `--files-only`: add `--skip-db`.

DDEV's provider integration pulls data, not Git code.

### Lando

Lando projects use `.lando.yml`. Checkout-specific settings can be placed in `.lando.local.yml`, which Lando loads after the shared Landofile.

The multidev workflow requires an existing `.lando.yml` and creates only the minimum local override needed for an isolated checkout. For Drupal sites it also corrects `DRUSH_OPTIONS_URI` to the isolated local app URL.

For data pulls, Pantheon Local Tools always passes explicit sources and disables code pulls.

Default database + files:

```text
lando pull --code=none --database=ENV --files=ENV
```

Database only:

```text
lando pull --code=none --database=ENV --files=none
```

Files only:

```text
lando pull --code=none --database=none --files=ENV
```

The explicit source values avoid Lando's default behavior of deriving unspecified sources from the current Git branch.

## Provider selection

Provider selection is command-sensitive.

For `multidev`, selection follows:

1. explicit `--provider ddev|lando`;
2. the configured default provider;
3. when the configured value is `auto`, unambiguous provider configuration found after cloning;
4. otherwise fail.

For `pull`, the existing checkout is authoritative:

1. explicit `--provider ddev|lando`;
2. provider recorded in Pantheon Local Tools checkout state;
3. unambiguous `.ddev/config.yaml` or `.lando.yml` detection;
4. otherwise fail.

The global default is intentionally not used to override an existing checkout's provider identity.

`auto` is detection, not permission to guess. If both provider configurations exist, an explicit provider is required unless Pantheon Local Tools already recorded which provider owns the checkout.

## Local state

Non-secret state lives inside the checkout's Git metadata:

```text
.git/pantheon-local-tools/state
```

Multidev records site/environment/Tag/provider/local identity. Successful pulls record database and files provenance independently:

```text
data.database-source=ENV
data.files-source=ENV
```

A full pull updates both. A component-only pull updates only the component that actually changed. Provenance is written only after the provider returns success and the tool verifies that Git `HEAD` and tracked content are unchanged.

Older state containing `data.source=ENV` is treated as both component sources and migrated losslessly on the next successful component-aware pull.

This state is local metadata, not application configuration, and is never committed.

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
- Never embed or collect Pantheon tokens, SSH keys, credentials, or organization-private values.
- Never start, rebuild, delete, or otherwise mutate a local runtime as an unrelated hidden side effect.
- Never perform a Pantheon remote write unless the user explicitly requested an operation that requires it.
- Pull database/files through documented provider interfaces rather than reimplementing synchronization.
- Pass explicit pull environments and component choices instead of inferring data provenance from the Git branch.
- Verify that data pulls did not change Git `HEAD` or tracked content before recording provenance.
- Record database/files provenance separately so a partial pull cannot misrepresent the untouched component.
- Fail on ambiguous Tag routing or provider selection instead of guessing.
- Keep organization-specific Pantheon Tags and directory mappings out of the repository.

## Upstream references

- Drupal local server setup: https://www.drupal.org/docs/develop/local-server-setup
- Pantheon DDEV guide: https://docs.pantheon.io/guides/local-development/ddev
- Pantheon local development guide: https://docs.pantheon.io/guides/local-development
- Pantheon Terminus commands: https://docs.pantheon.io/terminus/commands
- DDEV Pantheon integration: https://docs.ddev.com/en/stable/users/providers/pantheon/
- DDEV pull command: https://docs.ddev.com/en/stable/users/usage/commands/#pull
- Lando Pantheon syncing: https://docs.lando.dev/plugins/pantheon/sync.html
- Lando Landofile override files: https://docs.lando.dev/landofile/index.html
