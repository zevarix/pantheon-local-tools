# Local Checkout Status

`pantheon-local status` reports local checkout metadata without contacting Pantheon and without starting, stopping, rebuilding, or otherwise changing the selected local provider.

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
Local URL:       https://example-site-feature-a.example.test
URL source:      provider runtime
Git branch:      feature-a
Git tracking:    origin/feature-a
Git state:       clean
Database source: test
Files source:    live
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

## Provider URL discovery

The local provider is authoritative for the URL it actually serves. Pantheon Local Tools must not assume that every Lando project uses `*.lndo.site` or every DDEV project uses `*.ddev.site`.

When the provider executable is available, status performs a best-effort, read-only inspection:

- Lando: service URL data from `lando info`;
- DDEV: `primary_url` from `ddev describe -j`.

Status prefers an HTTPS non-loopback application URL when the provider reports multiple Lando URLs. Provider-specific extra services such as phpMyAdmin, Redis, Solr, MailHog, or custom services are not selected as the application's primary URL merely because they also expose URLs.

Runtime discovery is optional. If the provider is unavailable, stopped in a way that prevents inspection, or does not return a usable application URL, status falls back to the URL already recorded in local checkout state. If neither source is available, it reports `(not available)`.

`URL source` makes that distinction visible:

```text
URL source:      provider runtime
```

or:

```text
URL source:      recorded fallback
```

Status never starts or rebuilds a provider to discover a URL.

## Provider compatibility contract

Pantheon Local Tools is an additive orchestration layer around an existing local-development project. Provider-owned project configuration remains authoritative.

Status and URL discovery must not:

- rewrite or replace `.lando.yml` or `.ddev/config.yaml`;
- remove, rename, recreate, or reorder provider-defined services or tooling;
- alter Lando proxy definitions, custom domains, phpMyAdmin, Redis, Solr, MailHog, or other services;
- alter DDEV add-ons, `docker-compose.*.yaml` files, extra hostnames, or custom service definitions;
- start, stop, rebuild, or destroy the provider merely to obtain status information; or
- write a preferred hostname back into provider configuration.

This contract is covered by regression fixtures containing representative extra services and custom tooling. If future provider behavior cannot be inspected safely, status must fall back rather than mutate the project.

## Data provenance

Database and files sources are reported independently because local development workflows often refresh one without the other.

A successful full pull:

```bash
pantheon-local pull live
```

records `live` for both database and files.

A later database-only pull:

```bash
pantheon-local pull test --database-only
```

updates only the database source, so status can correctly report:

```text
Database source: test
Files source:    live
```

If a component has never been successfully pulled, status displays `(not recorded)`. It never infers data provenance from the current Git branch.

Older checkout state may contain a single legacy `data.source` value from releases before component-specific provenance. Status interprets that value as both database and files without modifying the state file. The next successful component-aware pull migrates that legacy value losslessly.

Provider failures or post-pull Git-safety failures do not update component provenance.

## Safety

`pantheon-local status` is local and read-only. It does not:

- contact Pantheon;
- require Terminus authentication;
- start, stop, rebuild, or destroy DDEV/Lando;
- alter Git state;
- write project files;
- rewrite provider configuration; or
- read or store machine tokens.
