# Real integration validation

This runbook defines real-host/provider validation procedures used for release qualification and ongoing compatibility evidence. It complements deterministic CI; it does not replace it.

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

# A. Real DDEV + Pantheon provider integration

## Purpose

Prove that the DDEV adapter works against a real Pantheon project without replacing project-owned DDEV configuration or allowing provider data transfer to mutate checked-out Git code.

The selected project must already contain valid `.ddev/config.yaml` and `.ddev/providers/pantheon.yaml`. Pantheon Local Tools deliberately does not synthesize a project's base DDEV setup.

DDEV's current Pantheon integration uses `DDEV_PANTHEON_SITE` and `DDEV_PANTHEON_ENVIRONMENT`; the older unprefixed variables are deprecated. DDEV provider pulls transfer database/files rather than Git code. Provider authentication remains DDEV-owned.

A real Pantheon Multidev command/clone path is already validated through the Lando provider. The additional combination of DDEV with an entitled real Pantheon Multidev is tracked separately in #24 and is not required to repeat the provider-runtime/data-transfer proof below.

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
PROJECT_ROOT='/path/to/disposable/pantheon-checkout'
DATA_ENV='SOURCE_ENV'
```

`PROJECT_ROOT` must be a safe disposable/local checkout whose current Pantheon code contains the DDEV project/provider configuration. `DATA_ENV` must be an environment safe and appropriate to copy into the local checkout.

## Use the exact release-candidate CLI and isolated user configuration

Validate from the exact current `main` commit intended for release testing. Use an isolated Pantheon Local Tools config so normal developer routing/configuration is untouched:

```bash
PLT_ROOT='/path/to/pantheon-local-tools'
CLI="$PLT_ROOT/bin/pantheon-local"

VALIDATION_ROOT=$(mktemp -d)
export PANTHEON_LOCAL_CONFIG="$VALIDATION_ROOT/config"

"$CLI" config set root "$VALIDATION_ROOT/checkouts"
"$CLI" config set provider ddev
"$CLI" config list
"$CLI" --version
```

The configured checkout root is intentionally disposable even when this validation operates on an already-cloned project. The provider pull/status commands should not need to write there.

## 1. Start DDEV

From the project checkout:

```bash
cd "$PROJECT_ROOT"
ddev start
ddev describe
```

Verify:

- DDEV starts successfully on the real host/container runtime;
- the project reports the expected Drupal/PHP/runtime configuration;
- the project-owned Pantheon provider recipe is detected; and
- tracked Git state remains clean.

## 2. Full real provider pull and Git-integrity proof

Capture the code state before the provider operation:

```bash
BEFORE_HEAD=$(git rev-parse HEAD)
BEFORE_DIFF=$(git diff --binary HEAD -- | git hash-object --stdin)

git --no-pager status --short --branch
```

Run the real provider path through Pantheon Local Tools:

```bash
"$CLI" pull "$DATA_ENV" --provider ddev
```

DDEV may take time while Pantheon generates/downloads data. The provider owns authentication and data-transfer behavior.

After success:

```bash
AFTER_HEAD=$(git rev-parse HEAD)
AFTER_DIFF=$(git diff --binary HEAD -- | git hash-object --stdin)

printf 'HEAD unchanged: %s\n' "$([ "$BEFORE_HEAD" = "$AFTER_HEAD" ] && printf yes || printf no)"
printf 'Tracked diff unchanged: %s\n' "$([ "$BEFORE_DIFF" = "$AFTER_DIFF" ] && printf yes || printf no)"

"$CLI" status
git --no-pager status --short --branch
```

Required result:

- the real DDEV Pantheon pull succeeds;
- `HEAD` is unchanged;
- tracked diff fingerprint is unchanged;
- `status` reports provider `ddev`;
- `status` records database and files provenance for `DATA_ENV`;
- the local URL comes from DDEV runtime metadata rather than an invented provider suffix;
- provider-owned project configuration remains intact; and
- no Pantheon Local Tools credential material appears in checkout state/config.

If a full files pull is unreasonably large for the selected project, do **not** silently redefine the release gate. Select a smaller representative environment or keep real DDEV files-transfer proof explicitly open while separately validating database-only behavior.

## 3. Component-selective behavior

After the full pull proof, exercise database-only selection:

```bash
"$CLI" pull "$DATA_ENV" --database-only
"$CLI" status
```

Verify the provider skips files and the recorded provenance remains truthful.

Also exercise files-only selection:

```bash
"$CLI" pull "$DATA_ENV" --files-only
"$CLI" status
```

Verify the provider skips the database and the recorded provenance remains truthful.

## 4. Credential boundary and final Git state

Inspect only Pantheon Local Tools-owned state/config, not provider credential stores:

```bash
STATE_FILE="$(git rev-parse --git-dir)/pantheon-local-tools/state"

if grep -RniE \
  'machine.?token|TERMINUS_MACHINE_TOKEN|password|secret' \
  "$PANTHEON_LOCAL_CONFIG" \
  "$STATE_FILE" \
  2>/dev/null; then
  printf 'FAIL: credential-like material found in Pantheon Local Tools state/config\n' >&2
  exit 1
else
  printf 'PASS: Pantheon Local Tools contains no provider credentials\n'
fi

git --no-pager status --short --branch
```

Required result:

- Pantheon Local Tools state/config contains no provider credential material; and
- final tracked Git state is clean.

## 5. Cleanup

Preserve failure evidence first. After a successful pass:

```bash
ddev stop
```

Remove only disposable validation paths after confirming each path is the intended one. The runbook intentionally does not provide a broad `rm -rf` copy/paste command.

### DDEV gate completion

The v0.1.0 real DDEV provider gate is complete when a real Pantheon-backed DDEV project passes startup, provider-derived status URL discovery, full database/files transfer, component-selective pulls, Git-integrity enforcement, provenance recording, credential separation, and final clean tracked state.

A real entitled **DDEV + Pantheon Multidev** combination remains valuable additional validation and is tracked separately in #24. Do not report that combination as completed unless it has actually run.

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

For the strongest WSL proof, install/configure Terminus and a supported local provider inside the same WSL environment and run the corresponding real status/pull integration rather than stopping at local tests.

If DDEV is used, this WSL pass can also satisfy the real DDEV provider gate **only if the complete DDEV checklist in section A passes**. Merely running `ddev --version` inside WSL does not satisfy the provider integration gate.

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
Real DDEV provider integration: PASS
- real Pantheon-backed DDEV project started successfully
- status URL derived from provider runtime metadata
- full database/files pull succeeded through DDEV
- database-only and files-only selections succeeded
- Git HEAD/tracked diff remained unchanged
- database/files provenance recorded correctly
- Pantheon Local Tools stored no provider credentials
- final tracked Git state clean

Private site/account/path/token details intentionally omitted.
```

If a separate real DDEV-on-Multidev pass is later completed, record it against #24 rather than folding it retroactively into this v0.1.0 provider proof.

Do not paste raw environment dumps or credential-bearing provider configuration into the public repository.