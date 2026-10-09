# Human interaction and guided remediation

Pantheon Local Tools uses one human-interaction model across interactive workflows:

```text
detect -> explain -> offer choices -> preview -> confirm -> delegate -> verify -> reassess
```

The goal is to keep the user in control without turning every command into a wall of prompts.

## Consent boundaries

PLT distinguishes two kinds of mutation entry points.

### Explicit mutation commands

When a user directly invokes a command whose documented purpose is to mutate state, that invocation is already an explicit action boundary. Examples include:

```text
pantheon-local checkout SITE.dev
pantheon-local checkout sync SITE.dev
pantheon-local setup
pantheon-local pull ENV
```

These commands should explain what they are doing, expose a dry-run/plan surface when their contract provides one, fail closed on ambiguity, and verify their result. They do not need an additional confirmation prompt merely for consistency.

### Guided or escalated mutation

When a flow begins read-only or advisory and then offers to perform a mutation, PLT must obtain explicit consent before crossing that boundary.

Examples include:

- Doctor offering to repair an actionable finding;
- guided configuration setup before writing configuration;
- `config export` before changing tracked Drupal configuration;
- `multidev create` before a remote Pantheon write.

Interactive mutation confirmation uses a safe default:

```text
Proceed? [y/N]
```

Pressing Enter means **No**. A user must explicitly answer yes for the mutation to proceed.

## Shared interaction primitives

Reusable prompt mechanics live in `libexec/pantheon-local-interaction`, separate from:

- `pantheon-local-terminal`, which owns styling, glyphs, and cursor behavior;
- `pantheon-local-output`, which owns structured JSON/record contracts;
- command implementations, which continue to own business logic and mutations.

The shared interaction layer owns bounded mechanics such as:

- yes/no confirmation with a default of No;
- numbered bounded choices;
- interactive-terminal availability checks.

Commands must not parse human terminal prose to decide what action to perform.

## Non-interactive behavior

Interactive prompts require a real input/prompt terminal.

- redirected and non-TTY commands never wait for input;
- automation uses explicit command arguments such as `--yes` where that command supports them;
- `--format json` remains machine-valid and prompt-free;
- durable operation records contain semantic results, not prompt chatter;
- `NO_COLOR` and `TERM=dumb` affect presentation only, never consent semantics.

A command must fail closed or remain read-only when a required interactive choice cannot be obtained.

## Guided remediation

Diagnostics use stable reason codes plus explicit remediation metadata.

Current remediation classes are:

- `plt-managed` — an existing PLT command owns a safe repair that can be offered after consent;
- `user-choice` — PLT can explain the bounded decision but must not guess;
- `external-action` — the required action belongs to an external authority/tool;
- `manual-recovery` — automatic repair would be unsafe;
- `none` — no remediation is required.

Remediation actions are stable identifiers such as `checkout-create`; they are not inferred by parsing diagnostic messages.

### Doctor

`pantheon-local doctor` remains read-only through diagnosis and report generation.

In an interactive terminal, after the report, Doctor may summarize actionable findings:

```text
Doctor found 3 items that need attention.

  ✓ 1 PLT-managed item
  ! 1 item needing your choice
  × 1 item requiring external action

PLT can fix now:
  1. Create canonical Dev checkout for example-site

Fix the 1 PLT-managed item now? [y/N]
```

If the user opts in, Doctor:

1. shows the owning command it intends to use;
2. executes the owning command's dry-run/preview when available;
3. asks again at the mutation boundary;
4. delegates to the owning command rather than reimplementing it;
5. respects the owning command's exit/result semantics;
6. verifies the owning command result, then offers (but never silently starts) another complete Doctor scan. The confirmation defaults to No because it may contact every accessible remote site. Repeated Tag overlaps are deduplicated using observed Tag membership, so guided review needs one preference per unique overlap and one optional rescan afterward.

Doctor does not automatically choose among ambiguous routes/providers or rewrite unsafe checkout identity. After a saved Tag-route preference, Doctor
continues the **same site's** Git and checkout/provider diagnostics using
previously observed Tag membership. It offers a missing canonical checkout
through the existing preview/confirmation/delegation path and then verifies
only the newly created local checkout, without automatically rescanning the
entire estate. No DDEV/Lando start, database pull, or project-configuration
selection happens implicitly. If neither provider's project configuration
exists, guided review asks **DDEV / Lando / Leave unresolved** (default);
that choice supplies instructions without persisting a provider setting or
synthesizing the provider-owned base configuration. Local `pantheon-local
status` can verify the checkout once the user configures the provider.

## Cancellation

Ctrl-C or termination during an interactive workflow must stop the current action according to the owning command's cancellation contract. It must not silently continue to later mutations.

A partially completed external mutation is reconciled through the owning authority before retry; PLT must not infer that a local interruption means a remote mutation did not occur.

## Product convention

New human-facing workflows should reuse this contract rather than inventing command-specific prompt conventions.

When reviewing an existing command, ask:

1. Is this command read-only, explicitly mutating, or escalating from read-only to mutation?
2. What authority owns the mutation?
3. Is user intent already explicit from the command invocation, or is a separate confirmation required?
4. Can the action be previewed?
5. How is the result verified?
6. What should the user do next when PLT cannot safely act?
