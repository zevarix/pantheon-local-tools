# Workflow model

Pantheon Local Tools uses one workflow model for existing built-in workflows, future built-in workflows, and downstream user/team workflows.

The workflow model is an orchestration layer. It does not replace the systems that own the underlying operations.

## Authority boundary

Pantheon remains authoritative for Pantheon state and operations.

When a workflow needs an atomic Pantheon read or mutation, PLT uses the documented Terminus command surface rather than implementing a parallel Pantheon API client. PLT may plan, select, invoke, verify, and reconcile a Terminus operation, but the Pantheon primitive remains owned by Terminus.

Local responsibilities remain with their normal owners:

- Git owns repository state;
- DDEV or Lando owns the local runtime and provider-specific operations;
- Drupal/Drush owns Drupal runtime operations;
- PLT owns orchestration, safety gates, local routing, workflow state, verification, and cross-system composition.

If a required Pantheon primitive is not safely exposed by Terminus, that is an upstream Terminus gap. A PLT workflow must fail closed or use another supported Terminus primitive rather than reimplementing Pantheon internals.

## Model

The shared model distinguishes three reusable concepts plus one invocation concept.

### Primitive

A primitive is one bounded inspect or mutation capability with one clear authority.

Examples include:

- inspect local Git status;
- start the selected local provider;
- run provider-owned Composer;
- pull a database through the selected provider;
- run provider-owned Drush;
- invoke a documented Terminus Pantheon command.

A primitive is not automatically a public top-level CLI command.

### Built-in workflow

A built-in workflow is a PLT-shipped composition of primitives.

Existing commands already fit this model:

- `pantheon-local setup` composes provider start, provider-owned Composer, guarded database pull, `drush updb`, and `drush cr`;
- `pantheon-local multidev create` composes Terminus Multidev creation, authoritative readback, and local checkout handoff;
- `pantheon-local config export` is a guarded composition of readiness, runtime inspection, explicit export, and Git verification.

Purpose-specific commands remain valid user interfaces. Internal workflow reuse does not require users to invoke a generic `workflow run` command.

### Downstream workflow

A downstream workflow is a user/team-owned composition and policy layer built from supported PLT workflow capabilities.

Downstream workflows may choose selectors, defaults, parameters, and verification rules appropriate to an estate. They may not weaken PLT safety gates or replace a Terminus-owned Pantheon mutation with a private direct-API implementation.

The external recipe/schema/discovery contract is tracked separately. The shared model defined here intentionally does not freeze a serialization format before that work is ready.

### Workflow run

A workflow run is one resolved invocation of a built-in or downstream workflow.

A run has:

- exact resolved targets;
- validated inputs;
- current phase and step;
- status;
- safe next action;
- evidence from the authoritative systems used by its primitives.

Structured operation records and stable machine-readable result schemas compose with this lifecycle model through the shared [`structured-output`](structured-output.md) contract.

## Phases

Not every workflow uses every phase, but consequential operations remain separable:

1. `select` — resolve exact targets without mutation;
2. `plan` — validate inputs and show intended operations;
3. `apply` — perform explicitly authorized mutations;
4. `verify` — re-read authoritative state after mutation;
5. `review` — expose resulting changes/evidence to a human or caller;
6. `commit` — explicit Git commit boundary when a workflow supports it;
7. `push` — explicit Git push boundary when a workflow supports it;
8. `complete` — record a finished/no-further-action state.

Planning does not grant mutation authority. Review does not imply commit. Commit does not imply push.

## Lifecycle state

Built-in workflows may persist compact checkout-local lifecycle state through the internal `pantheon-local-workflow-state` helper.

The current schema is version `1` and uses namespaced Git-config-compatible keys:

```text
workflow.<name>.schema
workflow.<name>.kind
workflow.<name>.phase
workflow.<name>.status
workflow.<name>.step
workflow.<name>.safe-next-action
workflow.<name>.updated-at
```

Supported lifecycle statuses are:

- `planned`;
- `in-progress`;
- `current`;
- `changed`;
- `partial`;
- `blocked`;
- `failed`;
- `complete`.

The helper updates its namespaced lifecycle fields through a temporary file and replacement so an interrupted write does not intentionally leave a half-written workflow record.

This compact state is not a complete operation log. Durable structured records, reason codes, exact primitive/authority fields, and multi-site result schemas belong to the structured-output work.

## Setup as the first reference built-in workflow

`pantheon-local setup` is the first existing command to record the shared workflow lifecycle while preserving its established `bootstrap.*` compatibility fields.

During execution it records:

- workflow: `setup`;
- kind: `built-in`;
- phase: `apply`;
- status: `in-progress` or `failed`;
- exact current setup step;
- a safe rerun action.

On success it records phase/status/step as `complete` with no remaining action.

A setup dry-run remains read-only and records no workflow lifecycle state.

## Resume and ambiguous effects

A workflow may only replay an operation when replay is known to be safe.

For local idempotent steps, a workflow can document that rerunning from the beginning is safe.

For remote Pantheon mutations, failure or interruption is not proof that the remote effect did not occur. A workflow must re-read Pantheon through Terminus and reconcile the authoritative state before retrying an ambiguous mutation.

Successfully verified remote effects are not automatically rolled back merely because a later workflow step fails.

## Public repository boundary

PLT core and its built-in examples remain organization-neutral. Site names, Pantheon Tags, local paths, modules, config objects, source-environment conventions, and other organization-specific policy belong in user/team configuration or downstream workflows.
