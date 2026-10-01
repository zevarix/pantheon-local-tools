# Canonical Pantheon Dev checkouts

`pantheon-local checkout` manages canonical local source checkouts for Pantheon `dev` environments.

This workflow is intentionally separate from Multidev checkout and from local runtime bootstrap. It discovers Pantheon state through Terminus, manages only local Git checkouts/PLT metadata, and never mutates a Pantheon environment.

## Commands

Single site:

```bash
pantheon-local checkout example-site.dev --dry-run
pantheon-local checkout example-site.dev
pantheon-local checkout sync example-site.dev
```

Estate population:

```bash
pantheon-local checkout dev --all --dry-run
pantheon-local checkout dev --tag 'Example Group'
pantheon-local checkout dev --tag 'Example Group' --tag 'Another Group'
```

Estate synchronization:

```bash
pantheon-local checkout sync --all
pantheon-local checkout sync --tag 'Example Group'
```

All forms support `--format default|json` and `--record FILE`. `--record` writes the same structured result to a new file and never overwrites an existing path.

## Pantheon authority

Pantheon-owned discovery is Terminus-backed.

The workflow uses supported Terminus surfaces for:

- accessible site inventory: `site:list`;
- site organization and Pantheon Tags: `site:info` + `tag:list`;
- Dev environment existence: `env:list`;
- canonical Dev Git connection: `connection:info SITE.dev --field=git_url`.

PLT does not add a direct Pantheon API client for canonical checkout discovery.

After Terminus supplies the canonical Git URL, Git remains authoritative for repository history and fast-forward safety.

## Destination routing

PLT uses the configured checkout root plus existing Pantheon Tag-to-directory routes.

For a site whose one matching configured route is:

```text
Example Group = clients
```

the canonical checkout destination is:

```text
<root>/clients/<site>
```

With no configured Tag routes, canonical checkouts live directly under `<root>/<site>`.

When Tag routes exist, a site must match exactly one configured route. Zero matches or multiple matches are `BLOCKED`; PLT never guesses a destination.

`--tag TAG` selects only sites carrying the named configured route. Repeating `--tag` uses OR selection. Estate results are ordered deterministically by site name.

## Classification

Before mutation, each selected site is classified:

| Action | Meaning |
| --- | --- |
| `CLONE` | Canonical destination does not exist. |
| `CURRENT` | Clean existing checkout exactly matches current Pantheon Dev Git HEAD. |
| `UPDATE` | Clean existing checkout is behind Pantheon Dev. |
| `SKIP` | Local state is preserved, such as a dirty checkout or missing checkout in sync mode. |
| `BLOCKED` | Destination/routing/origin/branch/history state is unsafe or ambiguous. |

Existing checkouts are checked against the Terminus-provided canonical Git URL and the remote default branch. PLT also compares local and remote history without modifying the checkout during planning.

Local-ahead or diverged history is `BLOCKED`; PLT never resets or force-updates it.

## Checkout mode

Normal checkout mode may create only missing canonical checkouts.

A clone is transactional:

1. create a temporary sibling directory;
2. clone the canonical Dev Git repository;
3. record checkout-local PLT identity under `.git/pantheon-local-tools/state`;
4. move the completed checkout into its final destination.

If clone/finalization fails, the final destination is not treated as completed.

A successful canonical clone records:

```text
pantheon.site
pantheon.environment = dev
pantheon.tag           (when routed by a configured Tag)
checkout.kind = canonical-dev
```

Provider configuration is not created or rewritten. Canonical checkout is source-estate setup, not provider/runtime bootstrap.

If an existing checkout is clean but behind, normal checkout reports `UPDATE` and leaves it untouched. This preserves an explicit update boundary.

## Sync mode

`pantheon-local checkout sync ...` is the only canonical-checkout update path.

For an `UPDATE` checkout, sync:

1. revalidates the clean working tree and expected branch;
2. fetches the canonical remote branch;
3. proves the local commit is an ancestor of the fetched remote branch;
4. performs `git merge --ff-only`;
5. verifies final `HEAD` matches the previously observed Pantheon Dev remote HEAD.

A missing checkout is `SKIP` in sync mode; sync never creates it. Run normal `checkout` first.

Dirty, wrong-origin, wrong-branch, local-ahead, or diverged checkouts are preserved unchanged.

## Multi-site execution and rerun

Estate execution is sequential and deterministic.

PLT plans every selected site first, then applies only safe `CLONE` or explicit sync `UPDATE` actions. A blocked/skipped site does not cause PLT to overwrite or roll back a different site that completed safely.

This makes rerun/resume idempotent: completed sites become `CURRENT`, while remaining missing/behind/blocked sites are reclassified from current authoritative state.

The workflow does not implement a separate concurrency subsystem; generalized bounded concurrency remains the responsibility of the shared workflow execution layer.

## Structured output and exit categories

JSON output composes with the shared [`structured-output`](structured-output.md) contract.

Each result includes:

- exact site and `dev` environment;
- action/state/reason code;
- destination and matched route Tag when known;
- canonical remote branch and SHA when known;
- safe next action;
- Terminus/Git authority metadata.

Important aggregate exit categories include:

- `0` — current/plan completed with no blocking condition;
- `10` — one or more local checkouts were cloned or fast-forwarded;
- `20` — selector produced no targets;
- `30` — unsafe local state (`SKIP`/`BLOCKED`);
- `31` — ambiguous/unmapped routing;
- `32` — required Terminus/Git authority unavailable;
- `33` — post-update verification failure;
- `40` — Git/orchestration operation failure.

A dry-run containing safe `CLONE`/`UPDATE` work reports aggregate structured state `planned` while remaining read-only.

## Explicit non-goals

Canonical checkout/sync does **not**:

- pull databases or files;
- start, stop, or rebuild DDEV/Lando;
- run Composer;
- run Drush or Drupal database updates;
- rebuild caches;
- export Drupal configuration;
- stage, commit, or push Git changes;
- create/delete/deploy/clone Pantheon environments.

After checkout, run `pantheon-local setup`, `pull`, `readiness`, or other workflows separately when those actions are actually desired.
