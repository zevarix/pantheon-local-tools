# Estate status and drift overview

`pantheon-local estate status` is the read-only cross-system overview for Pantheon sites and their canonical local Dev checkouts.

It combines authoritative Pantheon environment/code facts from Terminus with local Git, PLT checkout metadata, configured Tag routing, and provider detection. It does not start a provider or mutate local/remote state.

## Commands

Inspect one site:

```bash
pantheon-local estate status example-site
```

Inspect every accessible site:

```bash
pantheon-local estate status --all
```

Inspect configured Tag-selected subsets:

```bash
pantheon-local estate status --tag 'Example Group'
pantheon-local estate status --tag 'Example Group' --tag 'Another Group'
```

Repeated `--tag` uses OR selection. `--all` cannot be combined with `--tag`, and an exact site cannot be combined with estate selectors.

All forms support:

```text
--format default|json
--record FILE
```

`default` is the focused terminal table. JSON is the stable machine contract. A requested record writes that same JSON result to a new path and never overwrites an existing file.

## Remote authority

Pantheon-owned facts come from documented Terminus read surfaces:

- `site:list` for accessible site inventory;
- `site:info` + `tag:list` for Pantheon Tags;
- `env:list` for available environments;
- `env:code-log` for current Dev/Test/Live code commit identities where available;
- `connection:info SITE.dev --field=git_url` for the canonical Dev Git repository when local Git comparison is needed.

PLT does not add a direct Pantheon API client or scrape the Dashboard.

Git remains authoritative for the local checkout and canonical Dev repository history.

## Default table

The default terminal view keeps the columns focused:

```text
SITE                 TAG            LOCAL  BRANCH       CLEAN RELATION   PROVIDER  DEV      TEST     LIVE     STATUS
example-site         Example Group  true   master       true  current    lando     abc12345 abc12345 def67890 current
other-site           Apps           false  -            -     missing    -         789abcde 456def01 456def01 missing
```

Code identities are shortened for the terminal table. JSON retains the full hashes returned by Terminus.

## Local checkout interpretation

The canonical local destination uses the same root/Tag routing contract as `pantheon-local checkout`.

For a present Git checkout, estate status reports:

- current branch/ref;
- local `HEAD` SHA;
- clean/dirty working tree;
- canonical Git relation: `current`, `behind`, `ahead`, or `diverged`;
- selected provider from checkout-local PLT state when recorded, otherwise non-mutating DDEV/Lando project detection;
- canonical remote branch/SHA when Git authority is available.

Observed drift is information, not a failed inspection. Missing, behind, ahead, diverged, or dirty checkouts can still produce exit `0` when all required authorities were successfully inspected.

States needing attention use command-specific `assessment` values such as:

- `current`;
- `missing`;
- `behind`;
- `ahead`;
- `diverged`;
- `dirty`;
- `review`;
- `unavailable`.

A wrong origin, wrong canonical branch, ambiguous provider configuration, occupied destination, or checkout identity mismatch is reported as `review` rather than silently corrected.

## Routing

When configured Tag routes exist, each inspected site must match exactly one route for PLT to identify the canonical local destination.

- exactly one match: route is resolved;
- zero matches: routing is incomplete;
- multiple matches: routing is ambiguous.

Routing ambiguity returns the shared `ambiguous-configuration` category rather than guessing a local path.

With no configured Tag routes, canonical destinations are `<root>/<site>` and Tag reads are not required unless the user explicitly selected sites by Tag.

## Dev/Test/Live code identity

For each available environment, PLT reads the first commit hash reported by Terminus `env:code-log` as that environment's current code identity.

If an environment does not exist, its structured code status is `absent`. If its code log cannot be established, status is `unavailable` and the hash is `null` rather than guessed.

Environment code-log availability is reported independently so one unavailable code identity is not silently substituted from another environment.

## Structured output

JSON composes with the shared [`structured-output`](structured-output.md) contract.

Each selected site includes:

- `assessment` and `reason_code`;
- per-site `failure_source` when an inspection authority is incomplete;
- route status, matched Tag, and canonical destination;
- local checkout presence/destination state, branch/SHA, clean state, Git relation, provider/source;
- canonical remote Git branch/SHA when needed;
- independent Dev/Test/Live code status + full SHA.

Aggregate successful inspection uses:

- `result.state=current` / `estate-current` when every selected local checkout is current;
- `result.state=complete` / `estate-review-needed` when the inspection completed but observed drift/review states.

Stable nonzero categories are reserved for incomplete inspection:

- `20` / `no-targets` — selection matched nothing;
- `31` / `ambiguous-configuration` — local route cannot be resolved safely;
- `32` / `authority-unavailable` — required Terminus/Git authority could not be established;
- `40` / `operation-failed` — the inspection itself failed.

## Safety

Estate status never:

- starts, stops, or rebuilds DDEV/Lando;
- clones, pulls, fetches into, merges, resets, stages, commits, or pushes a local checkout;
- pulls databases/files;
- runs Composer or Drush;
- exports configuration;
- deploys, clones content, creates Multidevs, or otherwise mutates Pantheon.

The Git relation check uses isolated temporary repository state so it can compare histories without modifying the inspected checkout.
