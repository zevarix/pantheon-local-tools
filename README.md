# Pantheon Local Tools

Provider-neutral local development helpers for Pantheon workflows, with DDEV and Lando as the first supported local providers.

Pantheon Local Tools is being built to make common Pantheon local-development tasks safer and more repeatable without hard-coding one developer's machine layout, employer, organization naming conventions, Pantheon Tags, local directory mappings, or local development stack.

The initial release is being validated against Drupal projects. The shared Pantheon/Terminus core stays framework-neutral where doing so does not weaken safety or validation.

## Commands

Implemented command surfaces are:

```bash
pantheon-local config set root ~/sites/pantheon
pantheon-local config set provider ddev
pantheon-local config get provider
pantheon-local config tag set "Client Sites" clients
pantheon-local config tag list
pantheon-local config list
pantheon-local config path

pantheon-local multidev SITE.ENV
pantheon-local multidev SITE.ENV --dry-run
pantheon-local multidev SITE.ENV --provider lando --group migration
pantheon-local multidev SITE.ENV --provider ddev --start
```

Planned workflow commands are:

- `pantheon-local pull ENV` — refresh database/files for a normal local checkout without changing checked-out code.
- `pantheon-local status` — show the local checkout, selected provider, local URL, Git branch, and recorded Pantheon data source.

Convenience wrapper commands may be added after the canonical `pantheon-local` interface is stable.

## Configuration

Users do not need to hand-edit configuration files. `pantheon-local config` reads and writes a Git-compatible configuration file through Git's own parser.

By default the file is stored at:

```text
~/.config/pantheon-local-tools/config
```

If `XDG_CONFIG_HOME` is set, that location is respected. `PANTHEON_LOCAL_CONFIG` can override the complete path for automation and testing.

Built-in defaults are:

- `root`: `$HOME/sites/pantheon`
- `provider`: `auto`
- Pantheon Tag mappings: none

Examples:

```bash
pantheon-local config set root ~/work/pantheon
pantheon-local config set provider lando
pantheon-local config tag set "Internal" internal
pantheon-local config tag unset "Internal"
pantheon-local config unset provider
```

`config unset` removes the stored value and restores the built-in default where one exists. `config.example` documents the underlying file format, but the CLI is the recommended interface.

Organization-specific Pantheon Tags and local directory names belong only in user configuration and are never project defaults.

## Multidev checkouts

`pantheon-local multidev SITE.ENV` clones an **existing** Pantheon multidev environment into an isolated local checkout. It does not create, delete, or mutate the remote Pantheon environment.

The command:

1. verifies Terminus authentication;
2. resolves user-configured Pantheon Tag routing;
3. gets the authoritative Git URL from Terminus;
4. refuses to overwrite an existing destination;
5. clones into a temporary sibling checkout;
6. selects DDEV or Lando explicitly/configurably, failing on ambiguity;
7. writes only local provider overrides and records local state under `.git/`; and
8. finalizes the checkout only after local configuration succeeds.

`--dry-run` performs the read-only Pantheon lookups and prints the resolved plan without cloning or creating directories. `--start` is explicit; the tool never silently starts or rebuilds a local runtime.

With no configured Pantheon Tag routes, checkouts live below:

```text
<root>/multidev/<site>-<env>
```

With a Tag route such as `Client Sites -> clients`, the same checkout lives below:

```text
<root>/clients/multidev/<site>-<env>
```

Optional grouping adds one safe path segment:

```bash
pantheon-local multidev SITE.ENV --group migration
```

See [`docs/multidev.md`](docs/multidev.md) for the full safety and provider behavior contract.

## Terminus prerequisite

Pantheon Local Tools expects Terminus to already be installed and authenticated before commands access Pantheon. The tool detects missing authentication and fails with an actionable message rather than attempting to manage Pantheon credentials itself.

Pantheon's official documentation covers both installation and authentication:

- [Install and Update Terminus](https://docs.pantheon.io/terminus/install)
- [Create and manage machine tokens](https://docs.pantheon.io/machine-tokens)
- [`terminus auth:login` command reference](https://docs.pantheon.io/terminus/commands/auth-login)

A new Terminus installation generally needs a Pantheon machine token for its first authentication. Follow Pantheon's current instructions rather than storing a token in Pantheon Local Tools configuration. After authentication, `terminus auth:whoami` is a useful way to verify the active Pantheon identity.

## Local development providers

The first supported providers are **DDEV** and **Lando**.

Drupal.org recommends DDEV for Drupal local development, while existing Pantheon projects may use either DDEV or Lando. Pantheon Local Tools therefore keeps Pantheon and Terminus behavior in a shared core and delegates local-runtime behavior to provider-specific code.

Provider selection follows this order:

1. an explicit `--provider ddev` or `--provider lando` option;
2. the user's configured default provider;
3. when configuration is `auto`, unambiguous provider configuration found in the cloned project;
4. otherwise fail and ask the user to choose rather than guessing.

For multidev, DDEV requires an existing `.ddev/config.yaml` and receives a local `.ddev/config.local.yaml` name override. Lando requires an existing `.lando.yml` and receives a local `.lando.local.yml` name override; Drupal Lando projects also receive an isolated `DRUSH_OPTIONS_URI`.

Generated provider overrides are added to the checkout's `.git/info/exclude`; the project's shared `.gitignore` is not modified.

See [`docs/local-provider-architecture.md`](docs/local-provider-architecture.md) for the provider boundary and upstream references.

## Supported host environments

The command-line tooling targets:

- macOS;
- Linux; and
- Windows through WSL/WSL2.

On Windows, commands run inside the WSL Linux environment and use Linux paths. Native PowerShell and Command Prompt are not initial targets. The selected local provider must also be installed in a supported configuration for that host environment.

The shipped shell code intentionally avoids Bash 4-only features so it remains compatible with the older Bash supplied by macOS as well as modern Bash on Linux and WSL.

## Install from a clone

```bash
git clone git@github.com:zevarix/pantheon-local-tools.git
cd pantheon-local-tools
./install.sh
```

The installer creates a symlink at `~/.local/bin/pantheon-local` by default and refuses to overwrite an unrelated existing command. Set `PANTHEON_LOCAL_BIN_DIR` to choose a different destination.

A Homebrew installation path is planned for the first shareable tagged release. The clone installer remains the portable fallback for macOS, Linux, WSL, contributors, and CI.

## Development

Run the test suite directly:

```bash
for test in tests/test-*.sh; do
  bash "$test"
done
```

Run ShellCheck when available:

```bash
shellcheck bin/pantheon-local install.sh tests/test-*.sh
```

CI runs syntax validation, ShellCheck, and the test suite on both Ubuntu and macOS. WSL behavior is covered by Linux-path contract tests and will receive a real WSL integration pass before the first tagged release.

## Contributing

Contributions are welcome. See `CONTRIBUTING.md`.

## License

MIT license. See `LICENSE`.
