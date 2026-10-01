# Structured output and operation records

Pantheon Local Tools keeps its default terminal presentation separate from its machine-readable contract.

Commands that advertise structured output use:

```text
--format default
--format json
```

`default` selects the normal terminal presentation and is also the behavior when `--format` is omitted. JSON is the supported automation surface; scripts should not scrape spacing or labels from terminal output.

## Schema version

The initial structured schema version is `1`.

Every JSON result has a top-level `schema_version`. Additive fields may be introduced without changing the version. Removing a field, changing its type or meaning, or otherwise making an incompatible machine-contract change requires a new schema version.

Structured output is versioned independently from incidental terminal formatting and independently from the PLT package version.

## Common result envelope

Structured commands use a common envelope where applicable:

```json
{
  "schema_version": 1,
  "record_type": "inspection",
  "command": "status",
  "primitive": "local-status-inspection",
  "operation_id": null,
  "read_only": true,
  "result": {
    "state": "current",
    "reason_code": "status-observed",
    "exit_code": 0,
    "exit_category": "success",
    "failure_source": null,
    "next_action": null
  },
  "targets": [],
  "workflow": null
}
```

Command-specific objects may add Git, provider, Pantheon, Drupal, workflow, plan, verification, or other bounded facts. Fields that are unknown or not applicable use JSON `null` rather than terminal placeholders such as `(not recorded)`.

Target arrays are ordered. A command must preserve explicit caller order when that order is meaningful or use a documented deterministic ordering for discovered sets. The common JSON helper preserves the order supplied by the caller.

## Stable exit categories

Commands adopting this contract use these numeric categories:

| Code | Category | Meaning |
| ---: | --- | --- |
| `0` | `success` | Inspection/current state or successful operation with no separate changed result. |
| `10` | `changed` | Operation completed and produced intended changes. |
| `20` | `no-targets` | Selection completed successfully but resolved no targets. |
| `30` | `unsafe-local-state` | Dirty/conflicting/local state makes the requested action unsafe. |
| `31` | `ambiguous-configuration` | Routing/provider/selection configuration is ambiguous. |
| `32` | `authority-unavailable` | The authoritative system required to decide safely is unavailable. |
| `33` | `verification-failed` | An intended effect could not be verified against its owning authority. |
| `40` | `operation-failed` | The selected primitive or orchestration operation failed. |
| `64` | `usage-error` | Command arguments or structured-output options are invalid. |

These values are centrally defined by `libexec/pantheon-local-output`. New structured commands should reuse them instead of inventing command-specific numeric meanings.

A command may expose a more specific stable `reason_code` inside the JSON result while retaining one of these coarse exit categories.

`result.state` is the semantic outcome rather than a restatement of the numeric exit code. The initial shared vocabulary includes `current`, `planned`, `matched`, `excluded`, `skipped`, `changed`, `partial`, `blocked`, `failed`, and `complete`; commands should reuse an existing value when it fits rather than inventing synonyms.

`result.failure_source` is `null` for successful/current/planned results. Structured failures set it to the owning failure boundary so callers can distinguish failures such as `plt-orchestration`, `plt-verification`, `terminus`, `provider`, `git`, or `drupal`. A Terminus primitive failure must not be mislabeled as a PLT verification failure, and an unavailable/inconclusive post-mutation readback must not be reported as a successful primitive result.

## Workflow and authority fields

The common envelope composes with the workflow model in [`workflows.md`](workflows.md). When applicable, structured results should identify:

- built-in or downstream workflow name and workflow schema;
- one operation/workflow-run identity when a durable run identity exists;
- exact resolved targets;
- current phase and step;
- primitive identity;
- authority/source for observed facts;
- exact documented Terminus primitive intended or executed for Pantheon-owned actions;
- authoritative post-mutation readback;
- safe next/resume action.

A stateless inspection does not invent a workflow-run ID merely to populate a field; `operation_id` may be `null`.

Pantheon-owned actions remain Terminus-owned primitives. Structured output describes PLT's plan/orchestration/evidence and does not turn PLT into a second Pantheon API client.

## Durable operation records

Commands may support an explicit `--record FILE` option. A record contains the same JSON semantic result that the command exposes on stdout in JSON mode.

Record publication follows these safety rules:

- recording is explicit; read-only commands do not create records by default;
- the parent directory must already exist;
- an existing file or symlink is never overwritten;
- the record is written privately to a temporary file in the destination directory and atomically published without replacing an existing path;
- failure to publish the requested record is nonzero and does not silently claim durable evidence exists.

Operation records are bounded evidence, not logs or backups. They must not contain credentials, machine tokens, private keys, database contents, or raw secret-bearing provider/Terminus output.

Before attaching a locally generated record to a public issue, review ordinary identity fields such as local paths and site names under the repository's public-content rules.

## Command previews

When a consequential workflow can determine an exact supported action before mutation, its structured plan should include the primitive and sanitized command preview. For Pantheon mutations that means the documented Terminus primitive and non-secret arguments.

Never include authentication tokens, secret environment variables, or unfiltered provider output in a command preview.

## Reference consumers

`pantheon-local status` is the first inspection command that implements the shared contract:

```bash
pantheon-local status --format json
pantheon-local status --record ./status-result.json
pantheon-local status --format json --record ./status-result.json
```

`status` remains observational with respect to the checkout/provider. The only intentional write it can perform is the explicitly requested record file.

Its JSON includes local Git identity/state, PLT checkout identity, provider source/config/runtime URL evidence, component data provenance, bootstrap state, the shared `setup` workflow lifecycle when present, and explicit authority metadata showing that Pantheon was not contacted.

### Multidev creation plan

`pantheon-local multidev create` implements the structured planning boundary for its existing safe dry-run:

```bash
pantheon-local multidev create example-site.live feature1 --dry-run --format json
pantheon-local multidev create example-site.live feature1 --dry-run --record ./multidev-plan.json
```

After the normal Terminus authentication and `env:list` preflight succeeds, the plan reports Terminus as the Pantheon authority and includes the exact sanitized intended primitive as an ordered command-preview array equivalent to:

```text
terminus multidev:create example-site.live feature1 --yes
```

The structured dry-run never invokes that mutation. Real Multidev creation remains on its established default result surface until a later shared workflow-run/result consumer adopts the full mutation lifecycle.
### Canonical Dev checkout results

`pantheon-local checkout ... --format json` uses the common schema for both read-only plans and sequential checkout/sync results. Per-site records expose CLONE/CURRENT/UPDATE/SKIP/BLOCKED (or completed CLONED/UPDATED) state, reason codes, canonical destination, matched route Tag, remote branch/SHA, safe next action, and Terminus/Git authority.

A safe dry-run with missing/behind sites remains exit `0` and reports aggregate semantic state `planned`; a real run that clones or fast-forwards returns the stable `changed` category (`10`). Unsafe/ambiguous/unavailable/verification failures use the corresponding shared categories.
### Estate status inspection

`pantheon-local estate status ... --format json` emits read-only cross-system inspection records. Per-site results include assessment/reason/failure source, route/destination facts, local Git/provider facts, canonical remote Git identity when available, and independent Dev/Test/Live code-log status/full SHA. Ordinary drift such as missing/behind/ahead/diverged/dirty remains a successful complete inspection; nonzero categories represent incomplete routing or authority.
