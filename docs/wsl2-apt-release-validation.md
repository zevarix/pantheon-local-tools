# Disposable WSL2 APT release validation

Use this procedure for the real WSL2 previous-version -> current-version APT upgrade proof required by [`docs/releasing.md`](releasing.md).

The checked-in harness is:

```text
packaging/release/validate-wsl2-apt-upgrade.ps1
```

It is maintainer release-validation tooling, not an end-user installer. Run it from Windows PowerShell 7 against a separately created disposable WSL2 distribution. Never target a normal development distro or normal home directory.

## 1. Create a disposable WSL2 distribution

First inspect the installed/available WSL distributions from PowerShell:

```powershell
wsl.exe --version
wsl.exe --list --verbose
wsl.exe --list --online
```

Create a separate WSL2 distribution with an explicit name and location. This example uses Ubuntu 26.04; select a currently available Debian-family distribution appropriate to the release gate when that version is no longer current:

```powershell
$DistroName = 'PLT-release-test'

wsl.exe --install Ubuntu-26.04 `
  --name $DistroName `
  --location "$HOME\WSL\$DistroName" `
  --version 2 `
  --no-launch `
  --web-download

wsl.exe --list --verbose
```

Do not make the disposable distribution the Windows WSL default. The validation harness refuses to target whichever distribution is currently marked as default.

## 2. Run the reusable upgrade proof

Run the harness from a repository checkout so it can resolve the canonical APT repository URL and primary archive fingerprint from the checked-in `install-apt.sh` metadata:

```powershell
pwsh -NoProfile -File .\packaging\release\validate-wsl2-apt-upgrade.ps1 `
  -FromVersion '0.1.1' `
  -ToVersion '0.1.2' `
  -DistroName $DistroName `
  -ConfirmDisposableDistro
```

For a later release, replace the example versions with the actual previous and current published stable versions.

Optional OS assertions can pin the expected disposable image when a release tracker requires a specific WSL image:

```powershell
  -ExpectedOsId ubuntu `
  -ExpectedOsVersion '26.04'
```

The harness fails closed before PLT package operations unless all of the following are true:

- the explicit target distro exists and `wsl.exe --list --verbose` reports WSL version 2;
- the target is not the current default WSL distribution;
- `-ConfirmDisposableDistro` was supplied;
- the Linux runtime's `WSL_DISTRO_NAME` exactly matches the requested target;
- the Linux kernel reports WSL2;
- optional OS assertions match when supplied;
- PLT is not already installed and the dedicated PLT APT source/keyring are not already present;
- no prior evidence directory for the same version pair is present.

Before any PLT package operation, the harness creates/snapshots these disposable-user startup files:

```text
.bashrc
.bash_profile
.bash_login
.profile
.zshenv
.zprofile
.zshrc
.zlogin
.zlogout
```

It then:

1. installs only the APT validation prerequisites inside the disposable distro;
2. resolves the project-owned APT URL and primary fingerprint from `install-apt.sh` and verifies the downloaded archive key;
3. verifies both requested package versions are present in the signed public repository and that the current version is the live candidate;
4. installs the requested previous version and verifies the CLI version;
5. creates representative user-owned PLT configuration;
6. upgrades through APT to the requested current version and verifies CLI/config/shell-file preservation;
7. reinstalls the current version and rechecks preservation;
8. removes the package and verifies user configuration plus shell startup files remain intact;
9. writes and prints sanitized public-safe evidence; and
10. removes only the dedicated PLT APT source/keyring on success.

The PowerShell-to-Linux payload is transferred as UTF-8 bytes through Base64 so Windows CRLF/nested quoting cannot alter the embedded Bash program.

## 3. Review evidence before cleanup

The harness intentionally does **not** unregister the disposable distro. On success it prints the public-safe evidence and retains the full validation state inside the disposable distribution under:

```text
/root/pantheon-local-tools-wsl-validation/<FROM>-to-<TO>/
```

On failure it leaves the state/source/keyring/package state as observed and exits nonzero. Review the retained evidence before retrying or deleting the target. Prefer a fresh disposable distro for a clean release proof rather than silently overwriting failed evidence.

Do not publish machine-specific paths, local usernames, private site/account identifiers, credentials, or other private host state in a public issue. The generated `evidence.txt` intentionally omits the Windows machine name and explicit WSL distro name.

## 4. Remove the disposable distro manually

Only after the validation result has been reviewed and any required public-safe evidence has been recorded, remove the disposable target from PowerShell:

```powershell
wsl.exe --list --verbose
wsl.exe --terminate $DistroName
wsl.exe --unregister $DistroName
wsl.exe --list --verbose
```

`wsl.exe --unregister` permanently deletes that distribution's Linux filesystem. Verify `$DistroName` immediately before running it. The checked-in harness never performs this cleanup automatically.
