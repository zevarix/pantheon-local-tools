# Real integration validation

This runbook defines the remaining real-host/provider evidence required before the first public release. It complements deterministic CI; it does not replace it.

Keep real site names, account identities, machine tokens, UUIDs, organization Tags, private paths, and provider credentials out of public issues/commits. Record only sanitized outcomes in the public release tracker.

## Evidence rules

For every real pass:

- test the exact `main` commit intended for release validation;
- record host OS/runtime/provider versions privately while testing;
- preserve command output long enough to diagnose a failure;
- use `git --no-pager` for Git output that will be reviewed or pasted into a handoff;
- verify the final Git checkout is on the expected branch and has no unexpected tracked changes;
- do not publish machine tokens or other credential-bearing provider configuration;
- do not infer success from a neighboring platform or mocked CI test; and
- do not mark a release gate complete until the real command path named by that gate has run successfully.

---

# A. Real DDEV + Pantheon integration

## Purpose

Prove that the generic DDEV adapter works against a real Pantheon project without replacing project-owned DDEV configuration.

The selected Pantheon environment must already contain a valid project `.ddev/config.yaml` and `.ddev/providers/pantheon.yaml`, because `pantheon-local multidev` deliberately does not synthesize a project's base DDEV setup.

DDEV's current Pantheon integration uses `DDEV_PANTHEON_SITE` and `DDEV_PANTHEON_ENVIRONMENT`; the older unprefixed variables are deprecated. DDEV provider pulls transfer database/files rather than Git code. Provider authentication remains DDEV-owned.

Upstream references:

- https://docs.ddev.com/en/stable/users/providers/pantheon/
- https://docs.ddev.com/en/stable/users/providers/
- https://docs.ddev.com/en/stable/users/usage/commands/#pull

## Preconditions

From the host that will perform the pass:

```bash
git --version
terminus --version
ddev --version
docker version
```

Verify host Terminus authentication without exposing credentials:

```bash
terminus auth:whoami
```

Ensure DDEV's Pantheon provider authentication is configured through DDEV's supported local/global configuration. Do **not** paste the machine token into this runbook, a public issue, or a captured command transcript.

Choose privately:

```bash
TARGET='SITE.MULTIDEV_ENV'
DATA_ENV='SOURCE_ENV'
```

`TARGET` must be an existing Pantheon environment whose Git branch includes the DDEV project/provider configuration. `DATA_ENV` should be an environment safe and appropriate to copy into the disposable local checkout.

## Use isolated Pantheon Local Tools configuration

Do not disturb the developer's normal routing/config while validating.

```bash
VALIDATION_ROOT=$(mktemp -d)
export PANTHEON_LOCAL_CONFIG="$VALIDATION_ROOT/config"

pantheon-local config set root "$VALIDATION_ROOT/checkouts"
pantheon-local config set provider ddev
pantheon-local config list
```

The validation config intentionally contains no organization Tag mappings, so the disposable checkout should route directly below `<root>/multidev/`.

## 1. Dry-run

```bash
pantheon-local multidev "$TARGET" --dry-run
```

Verify:

- target site/environment is correct;
- provider is `ddev`;
- destination is under the isolated validation root;
- no destination directory is created; and
- no local URL is invented merely because DDEV was selected.

## 2. Clone and isolate

```bash
pantheon-local multidev "$TARGET"
```

Change into the created checkout path printed by the command, then inspect:

```bash
git --no-pager status --short --branch
cat .ddev/config.local.yaml
git --no-pager check-ignore -v .ddev/config.local.yaml || true
```

Verify:

- Git branch equals the Pantheon environment branch;
- `.ddev/config.yaml` remains project-owned and unchanged;
- `.ddev/config.local.yaml` contains only the isolated local project name written by Pantheon Local Tools;
- the generated local override is excluded from Git;
- provider-defined extra services/add-ons/hostnames/Compose files remain present; and
- tracked Git state is clean.

## 3. Start DDEV

```bash
ddev start
```

Then:

```bash
pantheon-local status
ddev describe -j
git --no-pager status --short --branch
```

Verify:

- DDEV starts the isolated checkout successfully;
- `pantheon-local status` reports provider `ddev`;
- the local URL comes from DDEV runtime metadata rather than an assumed `ddev.site` suffix;
- custom/additional hostnames are not rewritten by Pantheon Local Tools; and
- tracked Git remains clean.

## 4. Real data pull

First capture the code state:

```bash
BEFORE_HEAD=$(git rev-parse HEAD)
BEFORE_DIFF=$(git diff --binary HEAD -- | git hash-object --stdin)
```

Run the normal real provider path:

```bash
pantheon-local pull "$DATA_ENV"
```

DDEV may take time while Pantheon generates/downloads data. The provider owns its authentication and data-transfer prompts/errors.

After success:

```bash
AFTER_HEAD=$(git rev-parse HEAD)
AFTER_DIFF=$(git diff --binary HEAD -- | git hash-object --stdin)

printf 'HEAD unchanged: %s\n' "$([ "$BEFORE_HEAD" = "$AFTER_HEAD" ] && printf yes || printf no)"
printf 'Tracked diff unchanged: %s\n' "$([ "$BEFORE_DIFF" = "$AFTER_DIFF" ] && printf yes || printf no)"

pantheon-local status
git --no-pager status --short --branch
```

Required result:

- provider pull succeeds;
- `HEAD` is unchanged;
- tracked diff fingerprint is unchanged;
- status records database and files provenance for `DATA_ENV` after the full pull;
- runtime URL remains provider-derived; and
- no Pantheon Local Tools credential material appears in checkout state/config.

If a full files pull is unreasonably large for the selected project, do **not** silently redefine the release gate. Either select a smaller representative site/environment or keep real DDEV files-transfer proof explicitly open while separately validating database-only behavior.

## 5. Component-selective behavior

After the full pull proof, exercise at least database-only selection:

```bash
pantheon-local pull "$DATA_ENV" --database-only
pantheon-local status
```

Verify database provenance updates without falsely changing files provenance. If practical, also exercise:

```bash
pantheon-local pull "$DATA_ENV" --files-only
pantheon-local status
```

## 6. Cleanup

Preserve failure evidence first. After a successful pass:

```bash
ddev stop
```

Remove only the disposable validation root after confirming it is the intended path. The runbook intentionally does not provide a broad `rm -rf` copy/paste command.

### DDEV gate completion

The real DDEV release gate is complete only when clone/isolation, start, provider-derived status URL, full real data pull, Git-integrity proof, and provenance behavior all pass against a real Pantheon project.

---

# B. Real WSL2 integration

## Purpose

Prove the CLI behaves correctly inside an actual WSL2 Linux environment, including installation/path semantics that ordinary Linux CI cannot prove.

Current DDEV guidance recommends running DDEV commands inside WSL2 and storing projects in the WSL Linux filesystem (for example `/home/<user>/projects`) rather than `/mnt/c` for performance and permission behavior.

Upstream reference:

- https://docs.ddev.com/en/stable/users/install/ddev-installation/

## 1. Establish actual WSL state

From PowerShell, verify the intended distro is WSL2:

```powershell
wsl -l -v
```

Inside that WSL distro:

```bash
uname -a
cat /etc/os-release
bash --version | head -1
git --version
pwd -P
```

The validation checkout should live in the Linux filesystem, such as below `$HOME`, not a native Windows `C:\...` path.

## 2. Fresh clone and portable installer

Use a new disposable directory under the WSL home directory:

```bash
VALIDATION_ROOT=$(mktemp -d "$HOME/pantheon-local-tools-validation.XXXXXX")
cd "$VALIDATION_ROOT"

git clone https://github.com/zevarix/pantheon-local-tools.git
cd pantheon-local-tools

git --no-pager status --short --branch
./install.sh
```

If `$HOME/.local/bin` is not already in `PATH`, invoke the installed command by its explicit path for this validation rather than modifying shell startup files merely to make the test pass:

```bash
"$HOME/.local/bin/pantheon-local" --version
"$HOME/.local/bin/pantheon-local" version
```

Verify both report the repository `VERSION`.

## 3. WSL configuration/path contract

Use isolated configuration:

```bash
export PANTHEON_LOCAL_CONFIG="$VALIDATION_ROOT/config"
CLI="$HOME/.local/bin/pantheon-local"

"$CLI" config set root "$VALIDATION_ROOT/sites"
"$CLI" config set provider auto
"$CLI" config list
"$CLI" config path
```

Verify the stored root is a Linux absolute path.

Also verify a native Windows path is rejected:

```bash
if "$CLI" config set root 'C:\\Users\\Example\\sites' 2>/dev/null; then
  printf 'FAIL: native Windows path was accepted\n' >&2
  exit 1
else
  printf 'PASS: native Windows path rejected\n'
fi
```

A `/mnt/c/...` path is syntactically a Linux path and may be accepted by the CLI, although provider/project guidance may prefer the WSL filesystem for performance.

## 4. Run repository validation inside WSL

From the fresh clone:

```bash
for test in tests/test-*.sh; do
  bash "$test"
done
```

If ShellCheck is installed:

```bash
shellcheck bin/pantheon-local libexec/pantheon-local-* install.sh tests/test-*.sh packaging/debian/*.sh packaging/homebrew/*.sh packaging/release/*.sh
```

Verify no WSL-specific path/permission failure appears.

## 5. Real Pantheon/provider path when available

For the strongest WSL proof, install/configure Terminus and a supported local provider inside the same WSL environment and run the corresponding real multidev/status/pull integration rather than stopping at local tests.

If DDEV is used, this WSL pass can also satisfy the real DDEV gate **only if the complete DDEV checklist in section A passes**. Merely running `ddev --version` inside WSL does not satisfy the provider integration gate.

### WSL gate completion

The WSL release gate requires the actual WSL2 fresh clone/install, version/config/path contract, and full repository shell suite. Record any provider-specific WSL proof separately rather than inferring it from Ubuntu CI.

---

# C. Clean macOS clone/install smoke

## Purpose

Prove the documented portable clone install works from a genuinely fresh repository clone on a real macOS workstation, independent of an existing development checkout/symlink.

## Procedure

Use a disposable directory and an isolated installation bin so the existing command is not replaced:

```bash
VALIDATION_ROOT=$(mktemp -d)
cd "$VALIDATION_ROOT"

git clone https://github.com/zevarix/pantheon-local-tools.git
cd pantheon-local-tools

git --no-pager status --short --branch

export PANTHEON_LOCAL_BIN_DIR="$VALIDATION_ROOT/bin"
./install.sh

"$VALIDATION_ROOT/bin/pantheon-local" --version
"$VALIDATION_ROOT/bin/pantheon-local" version
```

Use isolated config and verify a write/read round trip:

```bash
export PANTHEON_LOCAL_CONFIG="$VALIDATION_ROOT/config"
CLI="$VALIDATION_ROOT/bin/pantheon-local"

"$CLI" config set root "$VALIDATION_ROOT/sites"
"$CLI" config set provider auto
"$CLI" config list
```

Run the repository test suite from the fresh clone:

```bash
for test in tests/test-*.sh; do
  bash "$test"
done
```

Verify the installer did not mutate shell startup files and the source checkout remains clean:

```bash
git --no-pager status --short --branch
```

The clean macOS gate is complete when the fresh clone, isolated install, canonical version, config round trip, and full tests pass on the real workstation.

---

# Sanitized public completion note

After a real pass, a public issue comment should report only generic evidence, for example:

```text
Real DDEV integration: PASS
- real existing Pantheon multidev cloned with DDEV provider
- isolated DDEV project started successfully
- status URL derived from provider runtime metadata
- explicit environment data pull succeeded
- Git HEAD/tracked diff unchanged
- database/files provenance recorded correctly
- no provider/project configuration clobbered

Private site/account/path/token details intentionally omitted.
```

Do not paste raw environment dumps or credential-bearing provider configuration into the public repository.