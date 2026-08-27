# Data Pull Workflow

`pantheon-local pull ENV` refreshes Pantheon data in an existing local checkout while preserving the currently checked-out Git code.

By default the command pulls both database and files:

```bash
pantheon-local pull dev
pantheon-local pull test
pantheon-local pull live
pantheon-local pull feature-a
```

When only one data component is needed, use an explicit selector:

```bash
pantheon-local pull live --database-only
pantheon-local pull live --files-only
```

`--database-only` and `--files-only` are mutually exclusive. Pantheon environment names are always passed explicitly; the tool never infers data provenance from the current Git branch.

A common Drupal module-update workflow is database-only: refresh the database from the desired Pantheon environment, run database updates locally, then export the resulting configuration without spending time synchronizing files that are irrelevant to the change.

## Provider selection

The command runs inside an existing Git checkout and resolves its provider in this order:

1. explicit `--provider ddev|lando`;
2. provider recorded in `.git/pantheon-local-tools/state`;
3. unambiguous DDEV/Lando project configuration;
4. otherwise fail and require an explicit provider.

The user's global default provider is not used to override an existing checkout's identity.

## Lando

Pantheon Local Tools always disables code pulls and passes every data source explicitly.

Both database and files:

```text
lando pull --code=none --database=ENV --files=ENV
```

Database only:

```text
lando pull --code=none --database=ENV --files=none
```

Files only:

```text
lando pull --code=none --database=none --files=ENV
```

Lando normally derives unspecified pull sources from the current Git branch. Pantheon Local Tools avoids that ambiguity by specifying the relevant sources explicitly and always setting `--code=none`.

Lando owns its Pantheon authentication interaction. If the Lando Pantheon plugin needs a machine token, it may prompt according to Lando's supported workflow. Pantheon Local Tools does not accept or store the token.

## DDEV

For DDEV, the project must contain:

```text
.ddev/config.yaml
.ddev/providers/pantheon.yaml
```

The command delegates to DDEV's Pantheon provider and sets the requested environment for that one pull:

```text
ddev pull pantheon --environment="DDEV_PANTHEON_ENVIRONMENT=ENV" -y
```

Database-only pulls add:

```text
--skip-files
```

Files-only pulls add:

```text
--skip-db
```

When Pantheon Local Tools already has the Pantheon site recorded in local checkout state, it supplies both values:

```text
DDEV_PANTHEON_SITE=SITE,DDEV_PANTHEON_ENVIRONMENT=ENV
```

This does not rewrite `.ddev/config.yaml` or the provider recipe. DDEV's Pantheon provider handles synchronization and does not pull Git code.

DDEV owns its machine-token configuration. Follow DDEV/Pantheon guidance for `TERMINUS_MACHINE_TOKEN`; Pantheon Local Tools does not collect or persist it.

## Git safety verification

Before delegating to the provider, Pantheon Local Tools records:

- the current Git `HEAD`; and
- a fingerprint of all tracked changes relative to `HEAD`.

After the provider returns successfully, both are checked again. If the provider changed `HEAD` or tracked content, the command exits with an error and does not record successful provenance.

This check intentionally ignores untracked/ignored files because a legitimate files pull writes CMS uploads into paths that are normally outside tracked source code.

The tool does not attempt an automatic rollback if a provider or project hook changes tracked code. It reports the violation so the developer can inspect the checkout rather than risking destructive recovery.

## Data provenance

Database and files provenance are recorded independently:

```text
data.database-source=ENV
data.files-source=ENV
```

inside:

```text
.git/pantheon-local-tools/state
```

A full pull updates both values. `--database-only` updates only `data.database-source`; `--files-only` updates only `data.files-source`.

Older checkouts may contain the pre-component key:

```text
data.source=ENV
```

`pantheon-local status` interprets that legacy value as the source for both database and files. On the first successful component-aware pull, Pantheon Local Tools migrates it into the two component keys before updating the requested component, preserving the provenance of the component that was not refreshed.

Provenance is recorded only after provider success and Git-safety verification. Failed provider pulls and Git-safety failures do not update it.

For an ordinary checkout that was not created by `pantheon-local multidev`, the first successful pull may create this local state file and record the detected provider plus component provenance.

## Non-goals

`pantheon-local pull` does not:

- merge, fetch, reset, or switch Git code;
- choose a data environment from the current branch;
- implement database dump/import or files synchronization itself;
- accept, echo, or persist Pantheon machine tokens;
- perform a Pantheon push; or
- automatically repair tracked code if a provider/project hook changes it.

## Upstream references

- DDEV Pantheon integration: https://docs.ddev.com/en/stable/users/providers/pantheon/
- DDEV pull command: https://docs.ddev.com/en/stable/users/usage/commands/#pull
- Lando Pantheon syncing: https://docs.lando.dev/plugins/pantheon/sync.html
- Lando Pantheon tooling: https://docs.lando.dev/plugins/pantheon/tooling.html
