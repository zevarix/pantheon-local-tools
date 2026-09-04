# Explicit Drupal configuration export

`pantheon-local config export` is the explicit tracked-source mutation boundary for exporting Drupal configuration from a Pantheon Local Tools-managed checkout.

Ordinary `pantheon-local readiness`, `pantheon-local status`, `pantheon-local setup`, Multidev checkout/start behavior, and Tag matching do **not** export configuration. A readiness report that shows differences never turns itself into a source mutation.

## Command

```bash
pantheon-local config export [--provider ddev|lando] [--yes]
```

Interactive example:

```bash
pantheon-local config export
```

Explicit non-interactive acknowledgement:

```bash
pantheon-local config export --yes
```

Provider override:

```bash
pantheon-local config export --provider ddev --yes
```

`--yes` acknowledges the tracked-source mutation without an interactive prompt. Non-interactive execution without that acknowledgement fails before the export command is run.

## Supported strategy

### `full-export`

Export is supported only when the checkout's recorded Pantheon Tag resolves to a valid `config-strategy=full-export` profile with an existing, physically contained `config-path`.

The configured path remains project data. PLT never assumes `config/sync` or another literal directory.

The actual mutation is provider-owned Drush:

```text
drush config:export -y
```

Drush documents `config:export` (`cex`) as exporting Drupal configuration to the site's configuration directory. PLT deliberately does not pass Drush `--add` or `--commit` and does not stage, commit, or push the result.

Upstream reference:

- Drush `config:export`: https://www.drush.org/13.x/commands/config_export/

### `overlay-delta`

Export is unsupported for `config-strategy=overlay-delta`.

A protected overlay/delta directory is a partial override set, not a complete Drupal export. PLT refuses this strategy before provider resolution or provider/Drush invocation. It never substitutes a generic `cex`, flattens shared/base configuration into the delta, or treats the delta path as a complete sync directory.

A future overlay mutation mechanism would require a separately proven owning-platform workflow. The current fail-closed readiness state does not establish one.

## Preflight

Before a full-export mutation, PLT performs this sequence:

```text
resolve recorded Tag/profile
→ require full-export strategy
→ validate configured path and physical project containment
→ require configured export path to be Git-clean
→ resolve provider
→ run the normal full-export readiness inspection
→ require Config Ignore module-state inspection to succeed
→ show the mutation plan
→ confirm interactively or require --yes
→ provider-owned drush config:export -y
→ report config-path changes and final Git status
```

The configured export path must have no pre-existing tracked or untracked Git changes. This is stricter than ordinary readiness on purpose: the post-export change report should represent the export operation rather than silently mixing newly generated YAML with unreviewed YAML that was already present.

Unrelated dirty files elsewhere in the checkout do not block export. They are preserved and remain visible in the final repository-wide Git status.

Readiness remains the inspection authority for the full-export runtime path. Before mutation it verifies that Drupal's runtime config-sync path corresponds to the profile's configured `config-path` and reports current configuration differences.

## Config Ignore

Config Ignore is Drupal runtime behavior, not a PLT strategy or duplicated PLT ruleset.

Current Config Ignore 3.x can apply ignore behavior on export as well as import, and its modes/settings may distinguish those directions. PLT therefore does not copy ignore patterns into its own persistent configuration or try to reproduce Config Ignore's decision logic.

Before mutation PLT requires enabled-module inspection to succeed:

```text
drush pm:list --type=module --status=enabled --field=name
```

If `config_ignore` is enabled, the mutation plan says so and reminds the user that Drupal/Config Ignore runtime export rules—including any runtime deactivation setting—remain authoritative. The provider-owned `drush config:export` then runs inside that actual Drupal runtime.

If module-state inspection is unavailable, export fails closed rather than guessing whether Config Ignore semantics may affect the tracked-source mutation. This is intentionally stricter than read-only readiness, where an unavailable Config Ignore state is advisory.

Upstream references:

- Config Ignore: https://www.drupal.org/project/config_ignore
- Config Ignore 3.4: https://www.drupal.org/project/config_ignore/releases/8.x-3.4
- Drush module list: https://www.drush.org/13.x/commands/pm_list/

## Confirmation

The command itself is explicit, but interactive use still receives a final mutation plan and confirmation prompt.

The plan includes:

- checkout directory;
- Pantheon Tag;
- strategy;
- configured export path;
- provider;
- Config Ignore module state;
- the provider-owned Drush mutation; and
- the fact that PLT will not commit or push.

`--yes` is the documented automation acknowledgement. It skips only PLT's confirmation prompt; it does **not** skip profile validation, clean-path enforcement, readiness, Config Ignore inspection, provider errors, or post-export reporting.

## Post-export report

Because the configured export path is required to be clean before mutation, PLT can report the resulting config-path change classes relative to `HEAD`:

```text
Export change summary for config/project-export:
  created: 2
  changed: 3
  deleted: 1
```

It then prints the complete repository-wide short Git status so unrelated pre-existing work is still visible.

PLT does not stage files. It does not auto-commit, auto-push, or modify a remote Pantheon environment.

Git `HEAD` is captured before and after the export. The command fails if `HEAD` changed, because PLT did not request Drush's commit behavior and an unexpected commit requires human inspection.

## Failure and retry behavior

A configuration export is not transactional. Provider-owned Drush can fail after writing some files.

If `drush config:export` exits nonzero, PLT:

1. does **not** claim success;
2. reports the resulting config-path change summary;
3. reports the final repository Git status;
4. preserves whatever local files now exist;
5. does not reset, stash, stage, commit, or roll back those files; and
6. exits nonzero with guidance to inspect the local changes before retrying.

That behavior avoids a more dangerous failure mode where an attempted automatic rollback could overwrite useful pre-existing or partially generated project state.

A retry is appropriate only after the developer has reviewed and resolved the reported local Git state. Because the configured export path must be clean before a new attempt, a partial previous export cannot be silently overwritten by another run.

## Remote boundary

`pantheon-local config export` is a **local Drupal/project-file mutation**. PLT does not issue a Pantheon remote write, create/delete a Multidev, commit Git changes, or push a branch as part of this command.

The provider must already be usable. PLT does not issue a provider start/rebuild command from config export.
