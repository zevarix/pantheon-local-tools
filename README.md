# Pantheon Local Tools

Local development helpers for Pantheon workflows across supported local development providers.

This project is being built to make common Pantheon local-development tasks safer and more repeatable without hard-coding one developer's machine layout, employer, organization naming conventions, Pantheon tags, local directory mappings, or local development stack.

## Planned commands

- `pantheon-multidev SITE.ENV` — clone a Pantheon multidev into an isolated local checkout and configure the selected local provider.
- `pantheon-pull ENV` — refresh database/files for a normal local checkout without changing checked-out code.
- `pantheon-status` — show the local checkout, selected provider, local URL, Git branch, and recorded Pantheon data source.

## Local development providers

The first supported providers are **DDEV** and **Lando**.

Drupal.org currently recommends DDEV for Drupal local development, while Pantheon documents both local-development approaches. Pantheon Local Tools therefore keeps Pantheon and Terminus behavior in a shared core and delegates provider-specific behavior to adapters.

Provider selection is designed to be explicit and fail-safe. The implementation will resolve the provider in this order:

1. an explicit command option such as `--provider ddev` or `--provider lando`;
2. the user's configured default provider;
3. an unambiguous provider configuration already present in the cloned project;
4. otherwise, fail and ask the user to choose rather than guessing.

Provider-specific local configuration must remain local to the developer's checkout. DDEV supports local `config.*.yaml` overrides such as `.ddev/config.local.yaml`; Lando checkouts can use `.lando.local.yml` for local overrides.

## Design goals

- Use Terminus as the authoritative source for Pantheon site/environment data.
- Keep Pantheon operations independent from the developer's local container provider.
- Keep local filesystem roots configurable per developer.
- Allow optional Pantheon tag-to-local-directory routing through user configuration.
- Keep all organization-specific prefixes, Pantheon tags, local directory mappings, and provider preferences in user configuration rather than source code.
- Configure isolated local names and URLs without committing machine-specific overrides to the Pantheon site repository.
- Never overwrite an existing checkout or silently choose between ambiguous providers.
- Treat environment start/rebuild operations and remote writes as explicit actions.

For example, one organization might map a Pantheon tag such as `Agency` to a local `agency/` directory while another developer may use no tag routing at all. One developer may use DDEV while another uses Lando. Those choices belong in each developer's local configuration and are not project defaults.

See [`docs/local-provider-architecture.md`](docs/local-provider-architecture.md) for the provider boundary and upstream references.

## Status

Early development. The first implementation is being validated against real Pantheon and Terminus environments with both DDEV and Lando provider behavior before the initial release.

## Requirements

The initial implementation targets macOS/Linux shells and expects:

- Git
- Bash
- Terminus
- at least one supported local provider: DDEV or Lando

Exact supported versions will be documented after integration testing.

## Contributing

Contributions are welcome. See `CONTRIBUTING.md`.

## License

MIT license. See `LICENSE`.
