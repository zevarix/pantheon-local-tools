# Contributing

Thanks for helping improve Pantheon Local Tools.

## Before you start

- Search existing issues and pull requests before opening a duplicate.
- For behavior changes, prefer opening an issue first so the intended workflow can be agreed on before implementation.
- Keep changes focused. Small pull requests are easier to review and safer to merge.

## Public repository hygiene

Pantheon Local Tools is a public repository. Repository code, commit messages, issues, pull requests, comments, examples, fixtures, logs, screenshots, and documentation must use generic public-safe identifiers.

Do not publish employer-, client-, organization-, institution-, internal-project-, private-site-, environment-, machine-, username-, directory-, or local-path identifiers. Replace real names with generic examples such as `example-site`, `Example Group`, `config/site-overrides`, or documented placeholders such as `SITE.ENV`.

Before opening or updating any public issue, pull request, or comment, sanitize copied commands, logs, paths, screenshots, configuration, and prose. If a real internal workflow is needed to validate behavior, keep the private evidence outside this repository and record only the generic product contract here.

## Development setup

The command-line tooling targets macOS, Linux, and Windows through WSL/WSL2. Native PowerShell and Command Prompt are not initial targets.

Development expects Git and Bash. Pantheon workflow integration additionally requires an authenticated Terminus installation and at least one supported local development provider. The first providers are DDEV and Lando.

Shell code shared across platforms should avoid Bash 4-only features so it remains usable with the older Bash supplied by macOS. WSL code should use Linux paths and must not assume native Windows path syntax.

Pantheon publishes the canonical Terminus setup and authentication guidance:

- https://docs.pantheon.io/terminus/install
- https://docs.pantheon.io/machine-tokens
- https://docs.pantheon.io/terminus/commands/auth-login

Never add machine tokens or other credentials to tests, fixtures, documentation examples, or repository configuration.

## Pull requests

1. Fork the repository or create a feature branch if you have write access.
2. Make the smallest coherent change that solves the problem.
3. Add or update tests for changed behavior.
4. Run the repository validation commands documented in the README.
5. Update documentation when user-visible behavior changes.
6. When changing provider behavior, validate the affected provider and avoid regressions in the other supported provider.
7. When changing portable shell behavior, consider macOS, Linux, and WSL path/shell semantics.
8. Sanitize issue/PR text, commits, examples, fixtures, logs, screenshots, and documentation so they contain only generic public-safe identifiers.
9. Open a pull request against `main` and explain what changed, why, and how it was tested.

The repository uses squash merging so each reviewed pull request becomes one canonical integration commit.

For public repository work, maintainers should use a GitHub noreply address for repository-local Git author and committer identity and keep GitHub email privacy protections enabled. Before treating a merge procedure as privacy-safe, verify both author and committer metadata on the resulting public commit do not expose a private email address.

## Safety expectations

This project interacts with developer environments and Pantheon sites. Changes must fail safely.

- Do not overwrite an existing checkout without explicit user action.
- Do not embed credentials, tokens, machine-specific paths, organization-specific Pantheon Tags, private naming conventions, or other internal identifiers.
- Treat remote writes, destructive local operations, and environment start/rebuild operations as explicit actions rather than hidden side effects.
- Prefer documented Terminus, DDEV, and Lando interfaces over scraping or guessing implementation details.
- Do not make shared Pantheon logic depend directly on one local provider.
- If provider detection or Pantheon Tag routing is ambiguous, fail and require an explicit choice instead of guessing.

## Reporting security issues

Do not open a public issue for a suspected vulnerability involving credentials, command injection, unsafe file writes, or another security-sensitive behavior. Follow `SECURITY.md` instead.
