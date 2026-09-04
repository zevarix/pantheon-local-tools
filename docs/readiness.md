# Drupal configuration readiness

`pantheon-local readiness` inspects whether a Pantheon Local Tools-managed Drupal checkout is ready for configuration review without exporting configuration or starting/rebuilding its local provider.

The command is intentionally strategy-aware. `full-export` can complete a provider/Drush-backed readiness inspection. `overlay-delta` is treated as a protected partial override set and is inspected only far enough to validate the configured boundary and Git state; it fails closed while a reliable owning validation mechanism is unavailable.

## Command

```bash
pantheon-local readiness [--provider ddev|lando]
```

Examples:

```bash
pantheon-local readiness
pantheon-local readiness --provider ddev
```

The provider must already be usable for `full-export`. Readiness never starts or rebuilds DDEV/Lando.

For `overlay-delta`, provider selection is not evaluated while owning validation is unavailable. A syntactically valid `--provider` value may be supplied, but no provider or Drush command is invoked.

## Profile authority

Readiness requires a PLT-managed checkout with a recorded `pantheon.tag`. That Tag resolves the existing Git-compatible profile created through `pantheon-local config tag profile`.

A `full-export` example:

```ini
[tag "Full Export Example"]
    directory = full-export-example
    config-strategy = full-export
    config-path = config/project-export
```

An `overlay-delta` example:

```ini
[tag "Protected Overlay Example"]
    directory = protected-overlay-example
    config-strategy = overlay-delta
    config-path = config/site-overrides
```

The path is user/project configuration. `config/sync` and `config/site-overrides` are examples, not PLT defaults or hard-coded assumptions.

Profile values are validated by the existing Tag-profile configuration seam. Readiness additionally requires the configured directory to exist and verifies that its physical filesystem location remains inside the Git project root. A project-relative path that resolves outside the checkout through a symlink or another filesystem link fails before provider/Drush behavior is considered.

If the recorded Tag has no complete profile, the configured directory does not exist, the path escapes the project root, or the strategy is unsupported, readiness fails before claiming a result.

## Full-export inspection

A successful full-export inspection performs these read-oriented steps:

```text
resolve recorded Tag/profile
→ verify configured config-path exists and stays inside the project root
→ resolve the selected provider
→ provider-owned drush core:status --field=config-sync
→ verify Drupal's runtime config-sync path matches the configured profile path
→ provider-owned drush config:status --format=list
→ provider-owned module-state inspection for Config Ignore
→ compare Git state before/after inspection
→ report final readiness
```

The runtime path check prevents a stale or incorrect profile from being treated as the project's actual full-export directory merely because that directory happens to exist.

Drush `config:status` reports active-versus-sync configuration differences. PLT treats non-empty list output as `differences detected` and empty list output as `synchronized`; it does not convert differences into an automatic export action.

## Overlay/delta inspection

An `overlay-delta` profile identifies a protected partial override set. The configured directory is **not** interpreted as Drupal's complete synchronization directory.

Current overlay inspection is deliberately bounded:

```text
resolve recorded Tag/profile
→ verify configured config-path exists and stays inside the project root
→ snapshot/report Git working-tree state
→ report the delta interpretation as a protected partial override set
→ report owning validation as unavailable
→ perform no provider/Drush/config-export action
→ exit nonzero
```

The command does not inspect the directory's contents to infer readiness. In particular:

- missing YAML does not imply drift;
- an empty directory does not imply drift;
- one file does not imply a valid or invalid delta;
- a large file count does not imply a full export;
- directory size has no readiness meaning;
- file names are not compared against active Drupal config as if the directory were complete.

Because the generic product does not yet have a reliable non-destructive command or comparison that represents every owning project's merge/import/update semantics, the report uses:

```text
Provider:              not invoked
Delta interpretation:  protected partial override set
Drupal configuration:  not interpreted as full export
Owning validation:     unavailable
Config Ignore:         not inspected
Config export:         not performed
Readiness:             unavailable
```

and exits nonzero.

That nonzero result is intentional. It means PLT successfully identified and protected the overlay boundary but **cannot yet make a readiness claim**. It must not convert missing knowledge into a green status.

A later implementation may replace `Owning validation: unavailable` only after a reliable generic or explicitly configured non-destructive validation mechanism is designed and tested. That later mechanism must preserve the same rule that the protected delta directory is not a complete export.

## Config Ignore

Config Ignore is an optional Drupal module/site characteristic used only by the current `full-export` readiness inspection. It is not a PLT profile strategy and is not inspected for `overlay-delta` while owning validation is unavailable.

For `full-export`, readiness asks Drupal for enabled module names through provider-owned Drush:

```text
drush pm:list --type=module --status=enabled --field=name
```

The report uses three states:

- `enabled` — `config_ignore` is reported as an enabled module;
- `disabled` — module inspection succeeds and `config_ignore` is not enabled;
- `unavailable` — module-state inspection could not be completed reliably.

`unavailable` is advisory rather than fatal after the core full-export configuration inspection has succeeded. PLT does not guess the missing state.

PLT deliberately does **not** reimplement Config Ignore's matching, import/export, or runtime semantics. When differences are present and Config Ignore is enabled—or its state is unavailable—the developer must review the Drupal/site-specific behavior before choosing any later export action.

Upstream references:

- Drush config status: https://www.drush.org/13.x/commands/config_status/
- Drush core status: https://www.drush.org/13.x/commands/core_status/
- Drush module list: https://www.drush.org/13.x/commands/pm_list/
- Drupal Config Ignore: https://www.drupal.org/project/config_ignore

## Git integrity

Full-export readiness snapshots both Git `HEAD` and the Git-visible working tree before running Drush inspection commands and checks them again afterward.

Overlay readiness does not run external provider/Drush inspection commands. It still reads `HEAD` and the working tree before reporting so a pre-existing dirty tree is visible and preserved.

A checkout may already be modified before inspection. That is a reportable state and does not authorize cleanup or reset.

For full-export, if the delegated inspection changes `HEAD` or changes the working tree relative to the pre-inspection snapshot, readiness fails instead of reporting success. A read-oriented inspection command is not allowed to silently become a source mutation path.

## Output and exit semantics

Synchronized full-export configuration and a clean working tree produce a result such as:

```text
Drupal configuration:  synchronized
Config Ignore:         disabled
Config export:         not performed
Git working tree:      clean
Readiness:             ready
```

Full-export configuration differences are reported conservatively:

```text
Drupal configuration:  differences detected
Config Ignore:         enabled
Config export:         not performed
Git working tree:      clean
Readiness:             review configuration differences
```

A pre-existing modified working tree is also surfaced for either strategy.

Exit semantics distinguish **inspection results** from **unsupported readiness claims** and **inspection failures**:

- exit `0` for a completed `full-export` inspection, including synchronized config, detected differences, Config Ignore enabled/disabled/unavailable, or a pre-existing modified Git working tree;
- exit nonzero for `overlay-delta` while the owning validation mechanism is unavailable, even though the command prints the known boundary/Git state;
- exit nonzero when PLT cannot inspect safely or completely, including incomplete/unsupported profile data, missing/escaping configured paths, provider/Drush failure, runtime config-path mismatch, or Git-visible mutation caused during full-export inspection.

The human-readable output is not a stable porcelain/JSON API.

## No export boundary

`pantheon-local readiness` never runs:

```text
drush config:export
drush cex
```

For `overlay-delta`, it also never runs `drush config:status` while the directory's owning validation semantics are unknown.

Readiness does not write YAML, recommend a blind export merely because differences exist, or treat an overlay directory as incomplete because files are absent.

Any future export capability is a separate explicit mutation boundary owned by #72.
