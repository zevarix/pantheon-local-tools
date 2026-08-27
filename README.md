# Pantheon Local Tools

Local development helpers for Pantheon and Lando workflows.

This project is being built to make common Pantheon local-development tasks safer and more repeatable without hard-coding one developer's machine layout or organization naming conventions.

## Planned commands

- `pantheon-multidev SITE.ENV` — clone a Pantheon multidev into an isolated local Lando checkout.
- `pantheon-pull ENV` — refresh database/files for a normal local checkout without changing checked-out code.
- `pantheon-status` — show the local checkout, Lando identity, local URL, Git branch, and recorded Pantheon data source.

## Design goals

- Use Terminus as the authoritative source for Pantheon site/environment data.
- Keep local filesystem roots configurable per developer.
- Support Pantheon site tags for routing sites into local project families.
- Generate per-checkout `.lando.local.yml` files for isolated multidev names and URLs.
- Fail safely rather than overwrite an existing checkout or guess when routing is ambiguous.
- Keep machine-specific configuration outside the repository.

## Status

Early development. The first implementation is being validated against real Pantheon, Terminus, and Lando environments before the initial release.

## Requirements

The initial implementation targets macOS/Linux shells and expects:

- Git
- Bash
- Terminus
- Lando

Exact supported versions will be documented after integration testing.

## Contributing

Contributions are welcome. See `CONTRIBUTING.md` once the initial project baseline lands.

## License

MIT license. See `LICENSE`.
