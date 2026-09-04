# Drupal configuration readiness

`pantheon-local readiness` inspects whether a Pantheon Local Tools-managed Drupal checkout is ready for configuration review without exporting configuration or starting/rebuilding its local provider.

The command is intentionally strategy-aware. Issue #70 implements the `full-export` strategy only; `overlay-delta` remains a separate safety problem owned by #71 and fails closed rather than inheriting full-export behavior.

## Command

```bash
pantheon-local readiness [--provider ddev|lando]
```

Examples:

```bash
pantheon-local readiness
pantheon-local readiness --provider ddev
```

The provider must already be usable. Readiness invokes provider-owned Drush but does not start or rebuild DDEV/Lando.

## Profile authority

Readiness requires a PLT-managed checkout with a recorded `pantheon.tag`. That Tag resolves the existing Git-compatible profile created through `pantheon-local config tag profile`.

For `full-export`, both properties are required:

```ini
[tag "Full Export Example"]
    directory = full-export-example
    config-strategy = full-export
    config-path = config/project-export
```

The path is user/project configuration. `config/sync` is a common example, not a PLT default or hard-coded assumption.

If the recorded Tag has no complete profile, the configured directory does not exist, the strategy is unsupported, or the provider cannot be resolved safely, readiness fails before claiming a result.

## Full-export inspection

A successful full-export inspection performs these read-oriented steps:

```text
resolve recorded Tag/profile
→ verify configured config-path exists
→ provider-owned drush core:status --field=config-sync
→ verify Drupal's runtime config-sync path matches the configured profile path
→ provider-owned drush config:status --format=list
→ provider-owned module-state inspection for Config Ignore
→ compare Git state before/after inspection
→ report final readiness
```

The runtime path check prevents a stale or incorrect profile from being treated as the project's actual full-export directory merely because that directory happens to exist.

Drush `config:status` reports active-versus-sync configuration differences. PLT treats non-empty list output as `differences detected` and empty list output as `synchronized`; it does not convert differences into an automatic export action.

## Config Ignore

Config Ignore is an optional Drupal module/site characteristic, not a PLT profile strategy.

Readiness asks Drupal for enabled module names through provider-owned Drush:

```text
drush pm:list --type=module --status=enabled --field=name
```

The report uses three states:

- `enabled` — `config_ignore` is reported as an enabled module;
- `disabled` — module inspection succeeds and `config_ignore` is not enabled;
- `unavailable` — module-state inspection could not be completed reliably.

`unavailable` is advisory rather than fatal after the core configuration inspection has succeeded. PLT does not guess the missing state.

PLT deliberately does **not** reimplement Config Ignore's matching, import/export, or runtime semantics. When differences are present and Config Ignore is enabled—or its state is unavailable—the developer must review the Drupal/site-specific behavior before choosing any later export action.

Upstream references:

- Drush config status: https://www.drush.org/13.x/commands/config_status/
- Drush core status: https://www.drush.org/13.x/commands/core_status/
- Drush module list: https://www.drush.org/13.x/commands/pm_list/
- Drupal Config Ignore: https://www.drupal.org/project/config_ignore

## Git integrity

Readiness snapshots both Git `HEAD` and the Git-visible working tree before running Drush inspection commands and checks them again afterward.

A checkout may already be modified before inspection. That is a reportable review state and does not make the inspection itself fail.

However, if the inspection changes `HEAD` or changes the working tree relative to the pre-inspection snapshot, readiness fails instead of reporting success. A read-oriented inspection command is not allowed to silently become a source mutation path.

## Output and exit semantics

Synchronized configuration and a clean working tree produce a result such as:

```text
Drupal configuration:  synchronized
Config Ignore:         disabled
Config export:         not performed
Git working tree:      clean
Readiness:             ready
```

Configuration differences are reported conservatively:

```text
Drupal configuration:  differences detected
Config Ignore:         enabled
Config export:         not performed
Git working tree:      clean
Readiness:             review configuration differences
```

A pre-existing modified working tree is also surfaced:

```text
Git working tree:      modified
Readiness:             review working tree
```

Exit semantics distinguish **inspection results** from **inspection failures**:

- exit `0` when inspection completed reliably, including synchronized config, detected differences, Config Ignore enabled/disabled/unavailable, or a pre-existing modified working tree;
- nonzero when PLT cannot inspect safely or completely, including incomplete/unsupported profile data, provider/Drush failure, runtime config-path mismatch, or Git-visible mutation caused during inspection.

The human-readable output is not a stable porcelain/JSON API.

## No export boundary

`pantheon-local readiness` never runs:

```text
drush config:export
drush cex
```

It does not write YAML, recommend a blind export merely because differences exist, or claim that a difference is erroneous simply because Config Ignore is enabled.

Any future export capability is a separate explicit mutation boundary owned by #72.

## Overlay/delta boundary

An `overlay-delta` profile identifies a protected partial/delta configuration workflow, not a complete sync directory. Issue #70 does not attempt to validate such a directory using full-export rules.

Until #71 establishes the owning platform/update mechanism and its safe inspection contract, `pantheon-local readiness` fails explicitly for `overlay-delta`.
