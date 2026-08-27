# Data Pull Workflow

`pantheon-local pull ENV` refreshes the local database and files from one Pantheon environment while preserving the currently checked-out Git code.

Examples:

```bash
pantheon-local pull dev
pantheon-local pull test
pantheon-local pull live
pantheon-local pull feature-a
```

Pantheon environment names are passed explicitly. The tool never infers database/files provenance from the current Git branch.

## Provider selection

The command runs inside an existing Git checkout and resolves its provider in this order:

1. explicit `--provider ddev|lando`;
2. provider recorded in `.git/pantheon-local-tools/state`;
3. unambiguous DDEV/Lando project configuration;
4. otherwise fail and require an explicit provider.

The user's global default provider is not used to override an existing checkout's identity.

## Lando

For a Lando Pantheon project, the command delegates to:

```text
lando pull --code=none --database=ENV --files=ENV
```

Lando normally derives unspecified pull sources from the current Git branch. Pantheon Local Tools supplies all three source options explicitly and sets `--code=none`, so only database/files are requested.

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

When Pantheon Local Tools already has the Pantheon site recorded in local checkout state, it supplies both values:

```text
DDEV_PANTHEON_SITE=SITE,DDEV_PANTHEON_ENVIRONMENT=ENV
```

This does not rewrite `.ddev/config.yaml` or the provider recipe. DDEV's Pantheon provider handles database/files synchronization and does not pull Git code.

DDEV owns its machine-token configuration. Follow DDEV/Pantheon guidance for `TERMINUS_MACHINE_TOKEN`; Pantheon Local Tools does not collect or persist it.

## Git safety verification

Before delegating to the provider, Pantheon Local Tools records:

- the current Git `HEAD`; and
- a fingerprint of all tracked changes relative to `HEAD`.

After the provider returns successfully, both are checked again. If the provider changed `HEAD` or tracked content, the command exits with an error and does not record a successful data source.

This check intentionally ignores untracked/ignored files because a legitimate files pull writes CMS uploads into paths that are normally outside tracked source code.

The tool does not attempt an automatic rollback if a provider or project hook changes tracked code. It reports the violation so the developer can inspect the checkout rather than risking destructive recovery.

## Data provenance

After a successful provider pull and successful Git safety verification, the command records:

```text
data.source=ENV
```

inside:

```text
.git/pantheon-local-tools/state
```

`pantheon-local status` then displays the recorded source. Provenance is recorded only after success; failed provider pulls and Git-safety failures do not update it.

For an ordinary checkout that was not created by `pantheon-local multidev`, the first successful pull may create this local state file and record the detected provider plus data source.

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
