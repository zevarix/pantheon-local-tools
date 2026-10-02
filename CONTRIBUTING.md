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

## CLI, output, and long-running work

User-visible commands should make their execution state understandable without weakening machine-readable contracts.

- Commands that may spend material time on sequential remote, provider, Git, Drupal, or estate-wide work must provide timely bounded progress in the default terminal experience so a healthy command does not appear hung. When a total target count is known, prefer phase plus current/total progress.
- Progress must remain useful in non-interactive/accessibility contexts. Prefer deterministic line-oriented feedback over spinner-only or cursor-control-only presentation.
- Progress/log chatter must not contaminate structured JSON stdout or durable operation records. Commands that advertise `--format json` must keep stdout machine-valid; progress belongs on stderr when it is emitted alongside a machine-readable mode. Operation records contain the final bounded semantic result, not progress logs.
- Reuse the shared terminal presentation helper for TTY detection, semantic glyphs/colors, headings, and cursor control instead of embedding command-specific ANSI sequences. Interactive color is supplemental, must respect `NO_COLOR`, and must fall back cleanly for `TERM=dumb`; redirected/non-TTY output must contain no ANSI/cursor-control sequences.
- Default terminal prose is not a machine API. New structured consumers should reuse the shared schema/versioning, exit-category, reason-code, authority, and record helpers rather than inventing command-specific machine contracts.
- Discovered multi-target sets and structured results must be deterministic. Preserve explicit caller order when it is meaningful; otherwise use a documented stable ordering.
- Unknown, unavailable, ambiguous, or inconclusive authority must remain explicit. Never report it as current, clean, synchronized, or successful merely to keep a workflow moving.
- Explicit user cancellation must stop long-running work. An interrupt such as Ctrl-C must not be converted into an ordinary child-step failure followed by continued targets, a normal final success/failure report, or publication of a partial operation record. Cleanup may run while the command exits with interrupt semantics.

## Human interaction and consent

Human-facing workflows follow the shared interaction contract documented in [`docs/interaction.md`](docs/interaction.md):

`detect -> explain -> offer choices -> preview -> confirm -> delegate -> verify -> reassess`

- Reuse `libexec/pantheon-local-interaction` for bounded yes/no confirmation and numbered choices rather than adding command-specific prompt dialects.
- A flow that escalates from read-only/advisory behavior to mutation must obtain explicit consent; mutation confirmation defaults to **No**.
- Directly invoked mutating commands do not require redundant prompts when the command invocation itself is the explicit action boundary, but they must still expose/describe their mutation boundary and fail closed on ambiguity.
- Prompts require a real terminal; JSON, operation records, and redirected/non-TTY execution remain prompt-free.
- Shared interaction code owns prompting mechanics only. The command that owns the mutation continues to own business logic, validation, execution, and verification.
- Never infer a remediation by parsing terminal prose. Use stable reason/action metadata and bounded explicit choices.
- Cancellation must stop the current interactive/remediation action rather than silently continuing to later mutations.

## Portability and test isolation

Cross-platform behavior must be proven without depending on a maintainer workstation's incidental state.

- Tests must explicitly control the state they depend on, including `HOME`, `PANTHEON_LOCAL_CONFIG`, relevant `PATH` entries, Git author identity for fixture commits, provider/Terminus mocks, and other environment inputs. Do not rely on a developer's global Git config, installed provider tools, authentication, shell aliases, or existing project files to make a fixture pass.
- Keep portable shell compatible with the older Bash shipped by macOS unless a command is explicitly platform-specific. CI ShellChecks files independently; runtime-resolved shared-library imports should use the narrowest justified ShellCheck annotation rather than relying on multi-file lint context.
- Windows/WSL validation must account for checkout and transport line endings. Shell payloads executed under Linux must arrive with Unix LF line endings; normalize embedded cross-OS payloads before byte-preserving transport and add regression coverage when Windows checkout conversion could affect execution.
- Fixtures should prove the actual safety boundary they claim. A missing-tool test, for example, must isolate `PATH` so a globally installed tool cannot silently satisfy the scenario.

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
- Treat documented Terminus commands as the owning interface for Pantheon reads and mutations; PLT may orchestrate and verify them, but must not add a parallel direct Pantheon API implementation for capabilities Terminus owns.
- Do not make shared Pantheon logic depend directly on one local provider.
- If provider detection or Pantheon Tag routing is ambiguous, fail and require an explicit choice instead of guessing.

## Reporting security issues

Do not open a public issue for a suspected vulnerability involving credentials, command injection, unsafe file writes, or another security-sensitive behavior. Follow `SECURITY.md` instead.
