# Release procedure

This document is the maintainer procedure for publishing Pantheon Local Tools. It complements the compatibility contract and provider-validation tracker; it does not waive any open release blocker.

## Release gates

Before tagging a release:

1. `main` must contain the intended release code and required CI must be green.
2. The release tracker must show the required real provider/host integration passes complete.
3. `VERSION` must contain the exact release version, without a development suffix for a final release.
4. `pantheon-local version` and `pantheon-local --version` must report that same version.
5. The public-content audit must be current and free of private organization/site/account/UUID/path/state values.
6. The documented compatibility contract must match the release behavior.
7. Clean install checks required by the release tracker must be complete.

Do not tag first and hope to repair the release afterward. Prepare the release version through an ordinary reviewed PR.

## 1. Prepare the release commit

For `v0.1.0`, update the repository-root `VERSION` from the development value to:

```text
0.1.0
```

Run the full repository validation matrix and merge only when required checks pass.

After merge, verify the exact release commit locally or through canonical GitHub state. When using Git locally, prefer explicit output without a pager for review commands, for example:

```bash
git --no-pager status --short --branch
git --no-pager log -1 --oneline
cat VERSION
```

The release working tree should be clean and the checked-out commit should be the intended `main` release commit.

## 2. Create the tag

Create the exact `vVERSION` tag only after the release commit is final:

```bash
VERSION=$(cat VERSION)
git tag -a "v$VERSION" -m "Pantheon Local Tools v$VERSION"
git push origin "v$VERSION"
```

Read the tag back and verify it resolves to the intended release commit.

The release artifact builder refuses a normal release build unless `vVERSION` exists and points at the current `HEAD`. CI/testing can opt into untagged builds only through the explicit `PANTHEON_LOCAL_RELEASE_ALLOW_UNTAGGED=1` test boundary.

## 3. Build deterministic release artifacts

From the exact tagged checkout:

```bash
bash packaging/release/build-artifacts.sh
```

The builder creates under `dist/`:

```text
pantheon-local-tools-<VERSION>.tar.gz
SHA256SUMS
```

On Debian-family hosts with `dpkg-deb` available it also creates:

```text
pantheon-local-tools_<VERSION>_all.deb
```

The source archive is produced with `git archive` and `gzip -n` using a stable top-level directory. `SHA256SUMS` records the source archive and every package artifact built in that run.

Build twice from the same exact ref if release confidence requires an additional reproducibility check; the source archive checksum must match.

## 4. Create the GitHub Release

Create a GitHub Release for the exact `vVERSION` tag and attach at least:

- `pantheon-local-tools-<VERSION>.tar.gz`;
- `SHA256SUMS`; and
- `pantheon-local-tools_<VERSION>_all.deb` when the Debian artifact is part of the release.

Do not upload artifacts built from a different commit than the release tag.

Release notes should summarize user-visible commands/behavior, compatibility guarantees, supported providers/hosts actually validated, known limitations, and installation options. Avoid environment-specific validation details or private identifiers.

After upload, download the published artifacts again and verify their SHA256 values against `SHA256SUMS` before using any artifact URL in package metadata.

## 5. Publish the Homebrew formula

The public tap is intended to be:

```text
zevarix/homebrew-tap
```

with the short tap name:

```text
zevarix/tap
```

Use the exact published release source asset URL and its verified SHA256 to render the formula:

```bash
VERSION=0.1.0
URL="https://github.com/zevarix/pantheon-local-tools/releases/download/v${VERSION}/pantheon-local-tools-${VERSION}.tar.gz"
SHA256="<verified published source artifact sha256>"

bash packaging/homebrew/render-formula.sh \
  "$VERSION" "$URL" "$SHA256" \
  Formula/pantheon-local-tools.rb
```

Commit the generated formula to `Formula/pantheon-local-tools.rb` in `zevarix/homebrew-tap`.

Never publish a formula that points to `main`, an unverified archive, or a placeholder checksum.

Validate the published formula with current Homebrew tooling, including the repository's required equivalents of:

```bash
brew install --build-from-source zevarix/tap/pantheon-local-tools
brew test zevarix/tap/pantheon-local-tools
brew audit --strict --new --online zevarix/tap/pantheon-local-tools
brew style zevarix/tap/pantheon-local-tools
```

Then verify the installed `pantheon-local --version`, configuration path/write/read behavior, and uninstall behavior.

The repository CI already proves the same formula layout through an isolated temporary tap before publication; the released tap check proves the actual end-user distribution path.

## 6. Validate the Debian release artifact

For a downloaded release package on Ubuntu/Debian:

```bash
sudo apt install ./pantheon-local-tools_<VERSION>_all.deb
pantheon-local --version
```

Verify user configuration remains outside package ownership and survives package removal/reinstallation.

Before advertising upgrade support, exercise a real previous-version -> current-version package upgrade. WSL/WSL2 requires its own real validation pass; Ubuntu CI is useful contract evidence but is not a substitute for WSL runtime proof.

A signed hosted APT repository is a separate distribution layer and does not become implied merely because a `.deb` exists.

When signed APT publication is enabled, `.github/workflows/publish-apt-repository.yml` assembles every stable published Debian package up to the target version, verifies each against its release `SHA256SUMS`, signs the resulting multiversion repository, validates it with an isolated APT client, and deploys the static tree to GitHub Pages. Pull requests exercise the same assembly/sign/validation path with an ephemeral key but never deploy.

Production APT publication requires the dedicated signing subkey secrets and GitHub Pages configured with **Source: GitHub Actions**. A manual workflow dispatch can bootstrap or republish an existing stable version; stable future release publication can trigger the same workflow automatically.

## 7. Post-release verification

After publication, verify:

- GitHub tag -> release commit identity;
- published release artifact checksums;
- `pantheon-local --version` through each advertised install method;
- clean Homebrew installation from `zevarix/tap`;
- Homebrew test and uninstall;
- Debian installation when shipped;
- configuration remains user-owned;
- no provider/project state is created merely by package installation; and
- the portable clone installer remains documented and functional.

Only then mark the corresponding release-tracker items complete.

## Recovery rule

If a published artifact or package metadata is wrong, preserve evidence and correct it explicitly. Do not silently move an existing release tag to different source bytes or replace a checksum without documenting the correction. Prefer a new patch release when users may already have consumed the published artifact.
