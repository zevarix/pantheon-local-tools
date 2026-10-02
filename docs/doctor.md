# Doctor diagnostics

`pantheon-local doctor` is the read-only first-run and troubleshooting diagnostic for Pantheon Local Tools.

It evaluates local prerequisites, effective configuration, Terminus authority, configured Tag routing, provider readiness, and canonical Dev checkout structure without repairing or mutating anything.

## Usage

```bash
pantheon-local doctor
pantheon-local doctor --format json
pantheon-local doctor --record ./doctor-result.json
```

`default` terminal output is a checklist. JSON is the supported automation surface. `--record FILE` writes that same JSON result to a new file and never overwrites an existing path.

## Progress

Default terminal mode keeps long remote/estate work visibly active without mixing progress text into structured output.

On an interactive terminal, each site uses one in-place status line. The active substep uses a Braille spinner while completed, failed, and not-yet-started substeps retain visible semantic markers:

```text
Doctor: site 2/34 · example-site — ✓ environments, ✓ organization, ⠹ tags, ○ routing, ○ Dev Git URL, ○ Git remote, ○ local checkout
```

Completed steps are green, the active step is bright cyan, pending/skipped steps are muted, warnings are yellow, and failures are red when color is available. Color is supplemental to glyph/text state, respects `NO_COLOR`, and is disabled for `TERM=dumb`.

The text cursor is hidden only while interactive progress animation is active and is restored before the final report and on cancellation/termination/cleanup so cursor repaint does not flash across the animated status markers.

When stderr is redirected or non-interactive, doctor emits deterministic line-oriented progress instead of cursor-control sequences, including the current site/substep:

```text
Doctor: inspecting site 2/34: example-site
Doctor: site 2/34: example-site — environments
Doctor: site 2/34: example-site — organization
Doctor: site 2/34: example-site — tags
```

`--format json` emits no progress text by default, so stdout remains one valid JSON document and stderr stays quiet. `--record FILE` stores only the final bounded diagnostic JSON; progress is never persisted in the record.

Interactive terminals also keep the final aggregation phase visibly active with the same Braille activity indicator while doctor summarizes checks and builds the final result. Finalization reads each stored check once per pass with Bash built-ins rather than launching a separate text-processing subprocess for every field.

## Interactive report

On an interactive stdout terminal, the final diagnostic report is grouped into Global, Sites, and Tags sections and uses the same semantic glyph/color vocabulary. Redirected/non-interactive stdout keeps the deterministic plain table form without ANSI sequences. WARN/FAIL details and their smallest known next actions remain visible in both forms.

## Cancellation

Ctrl-C cancels the entire doctor invocation. Doctor cleans its temporary diagnostic state and exits with conventional SIGINT status `130`; it does not reinterpret an interrupted Terminus/Git child as an ordinary per-site failure, continue to later sites, print the normal final diagnostic report, or publish a partial `--record` result.

Termination/hangup signals likewise stop doctor after cleanup rather than continuing estate inspection.

## Diagnostic statuses

Each check reports one of:

- `PASS` — ready/healthy;
- `INFO` — valid informational state; no repair required;
- `WARN` — recommended action, but diagnostic authority is complete;
- `FAIL` — a tool/configuration/authority condition prevents a safe workflow.

Warnings do not make the command fail. For example, a missing canonical checkout is a warning because the installation/configuration can still be healthy and the exact next action is `pantheon-local checkout SITE.dev`.

## What doctor checks

### Product and platform

- PLT `VERSION`;
- effective configuration file path;
- macOS/Linux/WSL platform detection.

A configuration file does not need to exist yet; PLT defaults remain valid until the file is created.

### Git and checkout root

- Git command availability;
- effective checkout root;
- whether an existing root is a directory;
- whether a not-yet-created root has a writable existing parent.

A missing root that can be created later is `INFO`, not failure. A root path occupied by a non-directory is an unsafe-local-state failure.

### Provider prerequisites

Doctor validates the configured global provider value and required command availability.

For canonical checkouts it mirrors the same provider precedence used by `setup`:

1. checkout-local recorded provider when present;
2. otherwise detect exactly one of `.ddev/config.yaml` or `.lando.yml`;
3. both or neither is an ambiguity failure;
4. the resolved provider command must exist.

Doctor does not run `ddev`, `lando`, Composer, or Drush.

### Terminus and Pantheon authority

Doctor verifies:

- Terminus command availability;
- `auth:whoami` succeeds;
- accessible site inventory can be read;
- each site's Dev environment is available;
- site organization/Tags can be read;
- canonical Dev connection information can be read;
- the canonical Git repository is reachable through Git.

Pantheon-owned facts come only from supported Terminus reads. Doctor does not scrape the Dashboard or add a direct Pantheon API client.

### Tag routing

Doctor reports configured Tag routes and validates their relative directory values.

For every accessible site it checks whether routing is resolvable:

- with no configured Tag routes, sites use `<root>/<site>`;
- with configured routes, each site must match exactly one configured Pantheon Tag;
- zero matches is an unmapped-route failure;
- multiple matches is an ambiguous-route failure.

Doctor also reports accessible Pantheon Tags that have no configured local route as `WARN`. Such a Tag does not automatically make a site's resolved route invalid when another configured Tag uniquely owns that site.

### Canonical Dev checkouts

For each resolvable accessible site doctor checks the canonical destination.

Missing checkouts are `WARN` with the exact checkout command.

For present Git checkouts doctor checks:

- checkout-local `pantheon.site`, `pantheon.environment`, and `checkout.kind` metadata;
- canonical origin against Terminus connection information;
- current branch against the canonical remote branch;
- recorded/detected provider project configuration;
- provider command availability.

Missing legacy PLT metadata can be informational when the checkout otherwise matches the canonical Git identity. Conflicting recorded metadata is a failure and is never rewritten automatically.

## Exit categories

Doctor uses the shared structured-output categories and chooses the highest-severity failed diagnostic:

- `0` — diagnostic completed; PASS/INFO/WARN only;
- `30` / `unsafe-local-state` — local root/checkout identity is unsafe;
- `31` / `ambiguous-configuration` — provider/routing/config ambiguity;
- `32` / `authority-unavailable` — required Terminus/Git authority cannot be established;
- `40` / `operation-failed` — a required local tool/prerequisite is unavailable or a diagnostic operation failed.

`result.failure_source` identifies the source of the highest-severity failure such as `git`, `terminus`, `ddev`, `lando`, or `plt-orchestration`.

Successful diagnostics use:

- `result.state=current`, reason `doctor-ready` when there are no warnings;
- `result.state=complete`, reason `doctor-warnings` when authority is complete but follow-up work is recommended.

## Structured checks

JSON check records include:

- stable check `id`;
- `status`;
- `reason_code`;
- optional shared `exit_category` for failures;
- `source`;
- concise `message`;
- smallest known `next_action`;
- `scope` such as `global`, `site:example-site`, or `tag:Example Group`.

Doctor records bounded diagnostics only. It does not include credentials, machine tokens, private keys, raw secret-bearing provider output, or database contents.

## Safety

Doctor never:

- starts/stops/rebuilds DDEV or Lando;
- clones, pulls, fetches into, merges, resets, stages, commits, or pushes a checkout;
- pulls databases/files;
- runs Composer/Drush;
- exports configuration;
- creates/stores credentials;
- edits PLT user configuration;
- deploys, clones content, creates Multidevs, or otherwise mutates Pantheon.

The only optional write is the explicitly requested operation record.

## Suggested first-run sequence

```bash
pantheon-local config init
pantheon-local doctor
pantheon-local checkout SITE.dev --dry-run
pantheon-local checkout SITE.dev
cd /path/to/checkout
pantheon-local setup --dry-run
```

Fix FAIL checks before relying on the affected workflow. WARN checks are review/action cues, not permission for doctor to repair them automatically.
