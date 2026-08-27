# Local Checkout Status

`pantheon-local status` reports local checkout metadata without contacting Pantheon and without starting, stopping, or otherwise changing the selected local provider.

Run it from the checkout root or any subdirectory:

```bash
pantheon-local status
```

A checkout created by `pantheon-local multidev` records non-secret metadata under Git's local metadata directory. Status reads that state and combines it with the current Git checkout state.

Example output:

```text
Pantheon Local Tools status

Directory:       /home/example/sites/client-a/multidev/example-site-feature-a
Managed:         yes
Pantheon:        example-site.feature-a
Tag:             Client Sites
Provider:        lando
Provider config: present
Local name:      example-site-feature-a
Local URL:       http://example-site-feature-a.lndo.site
Git branch:      feature-a
Git tracking:    origin/feature-a
Git state:       clean
Data source:     live
```

## Managed and existing checkouts

A checkout is reported as `Managed: yes` when Pantheon Local Tools state exists for it. Existing Git checkouts that were not created by the tool are still useful with `status`: DDEV or Lando is detected from an unambiguous project configuration, while Pantheon-specific values that have not been recorded are shown as `(not recorded)`.

A successful `pantheon-local pull` may create local Pantheon Local Tools state for an existing checkout so the detected provider and data provenance can be retained without modifying application files.

Status does not guess when both DDEV and Lando project configuration are present; it reports the provider as ambiguous unless local state already records which provider owns the checkout.

## Git information

Status reports:

- the repository root;
- the current branch, or a short detached-HEAD identifier;
- the configured upstream tracking branch when one exists; and
- whether tracked or untracked working-tree changes are present.

The command does not invoke a pager.

## Provider behavior

Status only checks whether the expected provider project configuration is present:

- DDEV: `.ddev/config.yaml`
- Lando: `.lando.yml`

It does not run `ddev`, `lando`, Docker, or Terminus. Runtime health and provider-discovered URLs can be added later without changing the local/offline status contract.

## Data source

After a successful `pantheon-local pull ENV`, status displays the environment recorded as `data.source` in local Git metadata.

If no successful database/files source has been recorded, status displays `(not recorded)`. It never infers data provenance from the current Git branch.

Provider failures or post-pull Git-safety failures do not update the recorded data source.

## Safety

`pantheon-local status` is local and read-only. It does not:

- contact Pantheon;
- require Terminus authentication;
- start or stop DDEV/Lando;
- alter Git state;
- write project files; or
- read or store machine tokens.
