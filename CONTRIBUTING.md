# Contributing

Thanks for helping improve Pantheon Local Tools.

## Before you start

- Search existing issues and pull requests before opening a duplicate.
- For behavior changes, prefer opening an issue first so the intended workflow can be agreed on before implementation.
- Keep changes focused. Small pull requests are easier to review and safer to merge.

## Development setup

The project targets macOS/Linux shell environments and expects Git, Bash, Terminus, and Lando.

Until the first stable release, supported versions and installation details may change as integration testing continues.

## Pull requests

1. Fork the repository or create a feature branch if you have write access.
2. Make the smallest coherent change that solves the problem.
3. Add or update tests for changed behavior.
4. Run the repository validation commands documented in the README.
5. Update documentation when user-visible behavior changes.
6. Open a pull request against `main` and explain what changed, why, and how it was tested.

The repository uses squash merging so each reviewed pull request becomes one canonical integration commit.

## Safety expectations

This project interacts with developer environments and Pantheon sites. Changes must fail safely.

- Do not overwrite an existing checkout without explicit user action.
- Do not embed credentials, tokens, machine-specific paths, or organization-specific secrets.
- Treat remote writes, destructive local operations, and environment rebuilds as explicit actions rather than hidden side effects.
- Prefer Terminus and Lando's documented interfaces over scraping or guessing implementation details.

## Reporting security issues

Do not open a public issue for a suspected vulnerability involving credentials, command injection, unsafe file writes, or another security-sensitive behavior. Follow `SECURITY.md` instead.
