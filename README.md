# Pantheon Local Tools

Provider-neutral local development helpers for Pantheon workflows, with DDEV and Lando as the first supported local providers.

Pantheon Local Tools is being built to make common Pantheon local-development tasks safer and more repeatable without hard-coding one developer's machine layout, employer, organization naming conventions, Pantheon Tags, local directory mappings, or local development stack.

## Commands

The first implemented command surface is the Git-style configuration interface:

```bash
pantheon-local config set root ~/sites/pantheon
pantheon-local config set provider ddev
pantheon-local config get provider
pantheon-local config tag set "Client Sites" clients
pantheon-local config tag list
pantheon-local config list
pantheon-local config path
```

Planned workflow commands are:

- `pantheon-local multidev SITE.ENV` — clone a Pantheon multidev into an isolated local checkout and configure the selected local provider.
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
- `site-prefix`: empty
- Pantheon Tag mappings: none

Examples:

```bash
pantheon-local config set root ~/work/pantheon
pantheon-local config set provider lando
pantheon-local config set site-prefix example
pantheon-local config tag set "Internal" internal
pantheon-local config tag unset "Internal"
pantheon-local config unset provider
```

`config unset` removes the stored value and restores the built-in default where one exists. `config.example` documents the underlying file format, but the CLI is the recommended interface.

Organization-specific site prefixes, Pantheon Tags, and local directory names belong only in user configuration and are never project defaults.

## Terminus prerequisite

Pantheon Local Tools expects Terminus to already be installed and authenticated before commands access Pantheon. The tool will detect missing prerequisites and fail with an actionable message rather than attempting to manage Pantheon credentials itself.

Pantheon's official documentation covers both installation and authentication:

- [Install and Update Terminus](https://docs.pantheon.io/terminus/install)
- [Create and manage machine tokens](https://docs.pantheon.io/machine-tokens)
- [`terminus auth:login` command reference](https://docs.pantheon.io/terminus/commands/auth-login)

A new Terminus installation generally needs a Pantheon machine token for its first authentication. Follow Pantheon's current instructions rather than storing a token in Pantheon Local Tools configuration. After authentication, `terminus auth:whoami` is a useful way to verify the active Pantheon identity.

## Local development providers

The first supported providers are **DDEV** and **Lando**.

Drupal.org currently recommends DDEV for Drupal local development, while existing Pantheon projects may use either DDEV, Lando, or another local workflow. Pantheon Local Tools therefore keeps Pantheon and Terminus behavior in a shared core and delegates provider-specific behavior to adapters.

Provider selection is designed to be explicit and fail-safe. Planned workflow commands resolve the provider in this order:

1. an explicit command option such as `--provider ddev` or `--provider lando`;
2. the user's configured default provider;
3. an unambiguous provider configuration already present in the cloned project;
4. otherwise, fail and ask the user to choose rather than guessing.

Provider-specific local configuration remains local to the developer's checkout. DDEV supports local `config.*.yaml` overrides such as `.ddev/config.local.yaml`; Lando checkouts can use `.lando.local.yml` for local overrides.

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

## Development

Run the config tests directly:

```bash
bash tests/test-config.sh
```

Run ShellCheck when available:

```bash
shellcheck bin/pantheon-local install.sh tests/test-config.sh
```

## Contributing

Contributions are welcome. See `CONTRIBUTING.md`.

## License

MIT license. See `LICENSE`.
