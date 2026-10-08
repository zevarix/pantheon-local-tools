# Doctor diagnostics

`pantheon-local doctor` is the first-run and troubleshooting diagnostic for Pantheon Local Tools.

Its diagnosis/report phase is read-only. It evaluates local prerequisites, effective configuration, Terminus authority, configured Tag routing, provider readiness, and canonical Dev checkout structure without mutation. In an interactive terminal, after the report, Doctor may offer guided remediation for findings that map to an existing PLT-owned repair workflow. No mutation occurs unless the user explicitly opts in and confirms the owning action.

## Usage

```bash
pantheon-local doctor
pantheon-local doctor --timing
pantheon-local doctor --format json
pantheon-local doctor --timing --format json
pantheon-local doctor --record ./doctor-result.json
```

`default` terminal output is a checklist. JSON is the supported automation surface. `--record FILE` writes that same JSON result to a new file and never overwrites an existing path.

## Progress

Default terminal mode keeps long remote/estate work visibly active without mixing progress text into structured output.

On an interactive terminal, Doctor keeps each animated site update on **one bounded physical row**. By default (`doctor-layout=auto`) it picks a layout **once for the whole discovered site list**, considering the longest site name and reserving space for timing and result labels. The layout does not switch as steps complete; only a physical terminal shrink can force a compact fallback to avoid wrapping. The original labelled status display is retained when the terminal is wide enough. For example:

```text
Doctor: site 2/34 · example-site — ✓ environments, ✓ organization, ⠹ tags, ○ routing, ○ Dev Git URL, ○ Git remote, ○ local checkout
```

On narrower terminals, Doctor switches to **fixed, aligned columns**. Columns always represent (in order) environments, organization, Tags, routing, Dev Git URL, Git remote, and local checkout. The site-name column uses a consistent width and abbreviates long names *only in the animated display*, never in the final report:

```text
Doctor:  1/34  example-site           │ ✓ ✓ ⠹ ○ ○ ○ ○ │ tags
Doctor:  2/34  another-site           │ ✓ ✓ ✓ × – – – │ × routing
    × Why: site another-site matches more than one configured local Tag route
      Next: confirm which configured Tag should take precedence
    – Not checked: Dev Git URL, Git remote, local checkout (stopped after routing failed)
```

The symbols describe the actual diagnostic steps: `✓` passed, `!` needs attention (warning), `×` failed, `–` was **not checked**, `○` is pending, and an animated Braille glyph is the current operation. Doctor prints the concrete cause and next action from its diagnostic records directly below a completed site with `!` or `×`. It also explains skipped (`–`) steps so an unchecked step cannot be mistaken for a failed check.

The `local checkout` step specifically inspects the **local canonical Pantheon Dev Git checkout**: location, repository identity, branch, PLT metadata when present, and provider configuration/availability. A checkmark here does **not** mean Lando/DDEV is running, that site data was pulled, or that code is synchronized to the latest remote commit.

To choose the presentation permanently:

```bash
pantheon-local config set doctor-layout auto
pantheon-local config set doctor-layout full
pantheon-local config set doctor-layout compact
```

`full` favors the original labelled display; if it cannot safely fit, the animated row is compact but a fully labelled static summary follows each site. `compact` always uses aligned columns. `auto` is the default. No choice changes JSON, decisions, checks, or repairs.

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

### Timing evidence

`--timing` is an opt-in troubleshooting surface for identifying slow external reads. It measures whole-second wall time around the external per-site boundaries for environments, organization, Tags, Dev Git URL, and Git remote inspection.

On an interactive terminal, the active step label includes the current elapsed time while the Braille spinner continues. Completed step durations remain visible on wide terminals; narrow terminals prioritize the active step:

```text
Doctor:  2/34  example-site           │ ✓ ✓ ⠹ ○ ○ ○ ○ │ tags (4s)
```

When stderr is redirected/non-interactive, timing mode emits a deterministic completion line after each timed boundary, for example:

```text
Doctor: site 2/34: example-site — environments complete in 6s
```

Timing evidence is diagnostic chatter only. It never changes the final semantic result, JSON stdout, or durable `--record` JSON. `--timing --format json` therefore keeps stdout as one valid JSON document while timing evidence remains on stderr.

`--timing` itself adds no retry policy or concurrency. Standard Doctor SSH Git remote checks use non-interactive key verification and SSH connect/idle limits rather than hanging indefinitely at a password or unknown-host prompt. A custom `GIT_SSH_COMMAND` is respected and may implement its own transport limits. A host-key mismatch is never automatically trusted; Doctor reports a specific next action without editing `known_hosts`. An SSH connect/idle limit is not a guaranteed total wall-clock deadline for every possible Git transport.

Interactive terminals also keep the final aggregation phase visibly active with the same Braille activity indicator while doctor summarizes checks and builds the final result. Finalization reads each stored check once per pass with Bash built-ins rather than launching a separate text-processing subprocess for every field.

## Interactive report

On an interactive stdout terminal, the final diagnostic report is grouped into Global, Sites, and Tags sections and uses the same semantic glyph/color vocabulary. Redirected/non-interactive stdout keeps the deterministic plain table form without ANSI sequences. WARN/FAIL details and their smallest known next actions remain visible in both forms.

### Repeat scans and local cache

After a saved routing preference or an explicitly confirmed PLT-managed repair, Doctor summarizes what it verified. It **does not** automatically repeat the full estate-wide scan. When multiple sites share the same overlapping Tag pair, one saved precedence rule is reused across the observed sites rather than asking for the same choice again; the review offers just **one** optional full rescan after all local preference changes. A separate `[y/N]` confirmation defaults to No; answer Yes only when a fresh set of network checks is wanted. Cached observed Tag membership can verify a local preference within the current process, but skipped Git or checkout checks remain unverified until a fresh scan.

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
- with configured routes, each site must resolve to one configured Pantheon Tag route;
- zero matches is an unmapped-route failure;
- multiple matches resolve only when explicit Tag precedence identifies one unique winner;
- unresolved multiple matches are an ambiguous-route failure.

For an unresolved overlap, guided review shows the concrete matching Tag routes. Doctor may recommend a preferred Tag when its observed site cohort is a strict subset of every other matching cohort, but the recommendation is never silently applied. The user can accept the recommendation, choose another matching route, or leave the overlap unresolved; saving a preference requires an additional explicit confirmation.

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

## Guided remediation

After the interactive report, Doctor classifies actionable WARN/FAIL findings as:

- `plt-managed` — an existing PLT command owns a safe repair that Doctor can offer;
- `user-choice` — PLT needs an explicit bounded user decision and must not guess;
- `external-action` — the action belongs to an external tool/authority;
- `manual-recovery` — automatic repair would be unsafe;
- `none` — no remediation is required.

When PLT-managed findings exist, Doctor summarizes them and asks whether to fix them. The default is **No**. For each accepted repair Doctor:

1. shows the owning PLT action;
2. runs the owning dry-run/preview when available;
3. asks again before mutation;
4. delegates to the owning command rather than reimplementing it;
5. verifies through that command's normal result/exit contract;
6. verifies the result and offers a full Doctor scan, explicitly confirmed with `[y/N]` defaulting to No. After a local Tag-route preference, Doctor first resolves the route from the Tag membership already observed in the current run; this cached verification does not claim fresh remote Git or checkout health.

The initial supported PLT-managed remediation is a missing canonical Dev checkout, delegated to `pantheon-local checkout SITE.dev`. Ambiguous Tag/provider decisions and unsafe checkout identity are never auto-selected or rewritten.

`--format json`, `--record`, and redirected/non-TTY use never prompt or mutate through guided remediation.

## Structured checks

JSON check records include:

- stable check `id`;
- `status`;
- `reason_code`;
- optional shared `exit_category` for failures;
- `source`;
- concise `message`;
- smallest known `next_action`;
- stable `remediation_class`;
- stable `remediation_action`;
- `scope` such as `global`, `site:example-site`, or `tag:Example Group`.

Doctor records bounded diagnostics only. It does not include credentials, machine tokens, private keys, raw secret-bearing provider output, or database contents.

## Safety

Doctor's diagnosis/report phase never mutates provider, Git, Drupal, PLT configuration, credentials, or Pantheon state.

Guided remediation is a separate opt-in phase. Doctor itself does not implement mutations; it delegates only to an existing PLT command that already owns the action and its safety contract. A repair must be explicitly confirmed, and actions with ambiguous intent or unsafe identity remain manual/user-choice findings.

The only write performed without entering guided remediation is the explicitly requested operation record.

## Suggested first-run sequence

```bash
pantheon-local config init
pantheon-local doctor
pantheon-local checkout SITE.dev --dry-run
pantheon-local checkout SITE.dev
cd /path/to/checkout
pantheon-local setup --dry-run
```

Fix FAIL checks before relying on the affected workflow. WARN checks are review/action cues. In an interactive terminal Doctor may offer supported repairs, but pressing Enter declines mutation and PLT never treats a finding itself as permission to change state.
