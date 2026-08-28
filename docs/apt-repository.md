# Signed APT repository

Pantheon Local Tools publishes its project website and signed Debian/Ubuntu/WSL repository from the same GitHub Pages origin:

```text
https://zevarix.github.io/pantheon-local-tools/
```

The root URL is the human-facing product page. APT clients consume signed metadata, package indexes, the public archive keyring, and package files beneath that same origin.

The repository uses the `stable` suite and `main` component. Client trust is scoped to a dedicated keyring through APT's `Signed-By` mechanism; `apt-key` is not used.

## Quick install

On Debian, Ubuntu, or WSL, the normal installation path is one command:

```bash
curl -fsSL https://raw.githubusercontent.com/zevarix/pantheon-local-tools/main/install-apt.sh | bash
```

The checked-in [`install-apt.sh`](../install-apt.sh) helper downloads the public archive keyring from the Pages repository, verifies the canonical primary fingerprint before making privileged changes, installs only the dedicated `Signed-By` keyring and deb822 source, refreshes APT, and installs `pantheon-local-tools`. It uses `sudo` only when the current user is not root.

The helper keeps the trust model described below; it only removes the repetitive setup steps. It fails before configuring APT if the downloaded keyring does not match the fingerprint embedded in the reviewed repository script.

Verify the installed command with:

```bash
pantheon-local --version
```

APT will use the published repository for later package upgrades when newer stable versions exist.

## Manual / auditable setup

The following procedure performs the same setup explicitly. Use it when you want to inspect each trust and configuration step rather than use the helper.

Install the small set of tools used to retrieve and verify the archive key:

```bash
sudo apt-get update
sudo apt-get install --yes ca-certificates curl gnupg
```

Download the public archive keyring and verify its primary fingerprint before installing it:

```bash
EXPECTED_FINGERPRINT='B75C45FA9E87AF56D7677F5785AF0D1C6E64C3F2'
KEYRING=$(mktemp)

curl --fail --silent --show-error --location \
  https://zevarix.github.io/pantheon-local-tools/pantheon-local-tools-archive-keyring.gpg \
  --output "$KEYRING"

ACTUAL_FINGERPRINT=$(
  gpg --batch --show-keys --with-colons "$KEYRING" |
    awk -F: '$1 == "fpr" && !found { print $10; found = 1 }'
)

[ "$ACTUAL_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ] || {
  printf 'archive key fingerprint mismatch: %s\n' "$ACTUAL_FINGERPRINT" >&2
  rm -f "$KEYRING"
  exit 1
}

sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 \
  "$KEYRING" \
  /etc/apt/keyrings/pantheon-local-tools.gpg
rm -f "$KEYRING"
```

Configure the repository with a deb822 source:

```bash
sudo tee /etc/apt/sources.list.d/pantheon-local-tools.sources >/dev/null <<'EOF'
Types: deb
URIs: https://zevarix.github.io/pantheon-local-tools
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/pantheon-local-tools.gpg
EOF

sudo apt-get update
sudo apt-get install pantheon-local-tools
```

## Remove the package or repository

Removing the Debian package does not remove user configuration or checkout-local state:

```bash
sudo apt-get remove pantheon-local-tools
```

To stop using the repository as well, remove only its dedicated source and keyring, then refresh APT:

```bash
sudo rm -f \
  /etc/apt/sources.list.d/pantheon-local-tools.sources \
  /etc/apt/keyrings/pantheon-local-tools.gpg
sudo apt-get update
```

## Publication trust model

The archive identity uses a certification-capable primary OpenPGP key kept out of normal online publication infrastructure. Repository metadata is signed by a separate signing subkey. GitHub Actions stores only the minimum passphrase-protected signing-subkey material needed to publish; the certification-capable primary secret is not stored in the repository, release assets, Pages content, workflow artifacts, or Actions signing secret.

The initial operational policy is:

- primary key: certification only, five-year expiration;
- signing subkey: signing only, one-year expiration;
- begin normal signing-subkey rotation at least 30 days before expiration;
- keep an encrypted full recovery bundle on offline/removable storage;
- keep the recovery-key passphrase separately from that backup; and
- publish only public key material to the APT repository.

The public primary fingerprint is:

```text
B75C45FA9E87AF56D7677F5785AF0D1C6E64C3F2
```

## Signing-subkey rotation

A signing-subkey rotation keeps the same primary archive identity, but clients still need a refreshed `/etc/apt/keyrings/pantheon-local-tools.gpg` containing the new subkey before repository metadata switches to that subkey. The primary fingerprint staying constant does **not** make an old local keyring learn new subkeys automatically.

Use an overlap procedure:

1. On a trusted offline system, restore the full recovery key and verify the expected primary fingerprint.
2. Add a new signing-only subkey while the previous signing subkey is still valid. Use an overlapping validity window; do not revoke or expire the old signer yet.
3. Export a refreshed public archive keyring and verify that the primary fingerprint is unchanged and that both the old and new signing subkeys are present.
4. Publish the refreshed public keyring and update the installation/rotation notice while repository metadata is still signed by the old subkey. When tooling contains multiple usable signing subkeys, select the old signing subkey explicitly rather than relying on GPG's implicit subkey choice.
5. Give existing clients a transition window to reinstall the dedicated keyring using the fingerprint-verified procedure above.
6. Replace the Actions signing-subkey export with the new minimum secret material, select the new signing subkey explicitly, manually republish the current stable repository, and verify the public `InRelease` signature plus a clean APT client.
7. Keep the old signing subkey valid through the announced overlap period. Retire or revoke it only after the transition is complete and the refreshed public keyring/recovery bundle is safely stored.
8. Record the new signing-subkey expiration and schedule the next rotation at least 30 days before it.

The repository publication workflow must never depend on automatic GPG subkey selection during a rotation involving multiple usable signing subkeys.

## Revocation and recovery

If the Actions signing secret is lost but the signing subkey is not suspected compromised, restore only the passphrase-protected signing-subkey export from the offline recovery bundle, replace the Actions secret, and manually republish the current stable repository. Verify the public signature and APT client path afterward.

If a signing subkey is suspected compromised, stop automated publication, restore the offline primary key, revoke the affected signing subkey, create a replacement signing subkey, and publish a refreshed public keyring with an explicit transition notice. Existing clients must refresh their dedicated keyring before metadata is signed only by the replacement subkey.

If the certification-capable primary key itself is lost or compromised, a new archive identity is required. Do not silently substitute a different primary key under the existing fingerprint documentation. Publish a migration notice, document the new fingerprint through an independently reviewable repository change, and require clients to replace the dedicated keyring explicitly.

Never place a private primary key, private signing subkey, passphrase, decrypted recovery bundle, or revocation secret in source control, release assets, Pages content, issue comments, or workflow logs.

## Validation status

The initial v0.1.0 repository was published through GitHub Pages with signed `InRelease`/`Release.gpg` metadata. The public WSL2 path was exercised through `apt update`, candidate discovery, install, CLI/config verification, reinstall with configuration preservation, uninstall, and package-file removal. `.github/workflows/validate-published-apt.yml` provides the corresponding clean GitHub-hosted Ubuntu validation against the public URL and now separately exercises the one-command bootstrap helper against that same public repository.

The product homepage is deployed as part of the same static Pages artifact without changing APT's signed metadata or trust path.

A real previous-version to newer-version upgrade remains deferred until a second stable Debian package has actually been published.
