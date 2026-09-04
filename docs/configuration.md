# Configuration and Pantheon Tag profiles

Pantheon Local Tools stores persistent user configuration in one Git-compatible file and uses Git's own `git config --file` parser/writer. The CLI is the supported management surface; the examples here show the on-disk representation only so the contract is auditable.

## Configuration file

The default path follows XDG conventions:

```text
~/.config/pantheon-local-tools/config
```

`XDG_CONFIG_HOME` changes the configuration root. `PANTHEON_LOCAL_CONFIG` supplies an explicit complete path for automation and tests.

Use:

```bash
pantheon-local config path
```

to print the active path.

The configuration file is Git-compatible data, not shell, YAML, JSON, or TOML. Pantheon Local Tools does not maintain a parallel profile file.

## Local defaults

The established local settings remain:

```ini
[local]
    root = ~/sites/pantheon
    provider = auto
```

Manage them with `config init`, `config get`, `config set`, `config unset`, and `config list` as documented by `pantheon-local help`.

## Pantheon Tag routing

A Pantheon Tag route maps a user-selected Pantheon Tag to a directory below the configured local root:

```bash
pantheon-local config tag set 'Example Group' example-group
pantheon-local config tag get 'Example Group'
pantheon-local config tag list
```

On disk, Git represents that mapping in the same tag subsection:

```ini
[tag "Example Group"]
    directory = example-group
```

Tag routing remains backward compatible. A route can exist with no configuration strategy at all.

## Optional Tag profile properties

Issue #68 extends the same `[tag "..."]` subsection with two optional properties consumed by setup/config-readiness work:

- `config-strategy` — one of `full-export` or `overlay-delta`;
- `config-path` — a relative project path such as `config/sync` or `config/site-overrides`.

Set them only after the Tag route exists:

```bash
pantheon-local config tag set 'Example Group' example-group
pantheon-local config tag profile set 'Example Group' config-strategy full-export
pantheon-local config tag profile set 'Example Group' config-path config/sync
```

Read or list them with:

```bash
pantheon-local config tag profile get 'Example Group' config-strategy
pantheon-local config tag profile get 'Example Group' config-path
pantheon-local config tag profile list 'Example Group'
pantheon-local config tag profile list
```

Remove one optional property without deleting the route:

```bash
pantheon-local config tag profile unset 'Example Group' config-path
```

Removing the Tag route removes its profile properties too:

```bash
pantheon-local config tag unset 'Example Group'
```

This avoids leaving profile state that no longer has a routable Pantheon Tag identity.

`pantheon-local config list` continues to print the established root/provider and `tag.TAG=DIRECTORY` route lines and may also print profile lines such as:

```text
tag.Example Group.config-strategy=full-export
tag.Example Group.config-path=config/sync
```

Human-readable output may gain labeled fields; it is not a structured/porcelain API.

## `full-export`

`full-export` identifies a project whose configured path represents its complete Drupal configuration export for the workflow Pantheon Local Tools inspects.

Generic example:

```ini
[tag "Full Export Example"]
    directory = full-export-example
    config-strategy = full-export
    config-path = config/project-export
```

The path is configurable. `config/sync` is a common example, not a product assumption.

For a PLT-managed checkout whose recorded Pantheon Tag resolves to a `full-export` profile, `pantheon-local readiness` requires both `config-strategy` and `config-path`, verifies that the configured directory exists and stays physically inside the project root, and checks that Drupal's runtime `config-sync` path corresponds to the configured profile path before interpreting `drush config:status` output.

Readiness reports synchronized/different configuration, Config Ignore module state when detectable, and the final Git working-tree state. It never performs `drush config:export` / `cex`. See [`readiness.md`](readiness.md) for the complete inspection and exit-status contract.

## `overlay-delta`

`overlay-delta` identifies a project where the configured path is a protected site-specific delta/override set rather than a complete Drupal export.

Generic example:

```ini
[tag "Protected Overlay Example"]
    directory = protected-overlay-example
    config-strategy = overlay-delta
    config-path = config/site-overrides
```

A delta directory may contain any subset of configuration files. Missing YAML, directory size, or file count does not imply drift. Pantheon Local Tools must not treat this profile as permission to run a blanket `drush cex` into the delta path.

`pantheon-local readiness` recognizes this strategy and validates only the generic boundary that PLT can establish safely:

- the Tag/profile resolves through the existing Git-compatible configuration model;
- the configured path passes the existing project-relative validation rules;
- the configured directory exists;
- its physical filesystem location remains inside the Git project root;
- the current Git working-tree state is reported and preserved.

While no reliable generic non-destructive owning validation mechanism is established, readiness does **not** invoke DDEV, Lando, or Drush for `overlay-delta`. It reports the path as a protected partial override set, reports `Owning validation: unavailable`, performs no export, and exits nonzero rather than claiming the project is ready.

That nonzero result is a safety state, not evidence that the delta is wrong. PLT intentionally does not classify empty, tiny, or large delta sets as drift and does not compare missing files against complete active Drupal configuration.

A future owning-validation implementation must preserve this boundary and may only replace the unavailable state when it has an explicit reliable non-destructive mechanism for the relevant merge/import/update semantics.

## Validation and failure behavior

Profile values are validated when they are set and again when they are read. Pantheon Local Tools fails rather than guessing when hand-edited configuration contains an unsupported strategy or unsafe path.

`config-strategy` accepts only:

```text
full-export
overlay-delta
```

`config-path` must:

- be non-empty;
- be relative to the project root;
- use forward slashes;
- contain no newline;
- contain no empty path segment (`//`);
- contain no `.` or `..` path segment.

Readiness adds a filesystem-boundary check: even a lexically valid relative path is rejected if the configured directory resolves outside the Git project root through a symlink or another filesystem link.

A profile setter refuses a Pantheon Tag that has no existing `directory` route. This keeps routing identity explicit and prevents configuration-only subsections from silently changing Multidev Tag matching.

The two properties are independently optional so users can build or edit a profile incrementally. A command that requires a complete strategy/path pair validates that requirement itself and fails closed when the profile is incomplete. `pantheon-local readiness` is such a consumer for both supported strategy labels.

## Organization-specific values

Pantheon Local Tools does not contain built-in organization-specific Pantheon Tags, directory names, or config paths. Values such as `config/sync` are examples/proving-ground configuration only.

Another organization can use the same strategies with completely different Pantheon Tags, routing directories, and project-relative configuration paths.

## Security and authority boundary

The profile is declarative routing/setup metadata. It does not grant permission to:

- create or delete Pantheon Multidevs;
- mutate remote Pantheon environments;
- start providers;
- pull databases/files;
- run Composer;
- export Drupal configuration;
- commit or push project changes.

A consumer such as `pantheon-local readiness` may run explicitly documented provider-owned, read-oriented Drush inspection commands only when its strategy contract calls for them. Current `overlay-delta` readiness does not invoke provider-owned commands while owning validation semantics remain unavailable. Each consumer remains responsible for its own runtime, mutation, failure, and Git-integrity boundaries.
