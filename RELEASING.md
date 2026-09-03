# Releasing Mergelio

Mergelio follows [Semantic Versioning](https://semver.org). The version lives in
`pubspec.yaml` as `version: <semver>+<build>` (e.g. `1.4.0+14`).

Pushing a `v*` tag builds, signs and packages every platform in GitHub Actions
and leaves a draft release to check and publish by hand — see [Release
pipeline](#release-pipeline). The same build scripts also run locally, one
platform at a time: they refuse to cross-compile, so a local artifact has to be
built on a host of the matching platform.

## Checklist

1. **Match the pinned toolchain** — Flutter 3.44.6 (`.fvmrc`). The build
   scripts warn when the running SDK differs; a newer one breaks code
   generation. `make doctor` covers the rest of the environment.
2. **Green tree** — `make check` (formatting, `flutter analyze`, full test
   suite). `make ci` also refetches dependencies and regenerates sources first.
3. **Bump the version** — `./scripts/bump-patch.sh`, `bump-minor.sh` or
   `bump-major.sh`. Each rewrites `version:` in `pubspec.yaml`; the build number
   always grows, and the lower components reset when a higher one moves.
4. **Regenerate icons** if the brand master changed:
   `dart run flutter_launcher_icons` (configured in `pubspec.yaml`).
5. **Localization** — every key in `lib/l10n/app_en.arb` needs a counterpart in
   `lib/l10n/app_uk.arb`. After editing either, run `flutter gen-l10n` and
   commit the result: unlike freezed and drift output, `lib/l10n/gen/` is
   tracked.
6. **Land the version bump** on `main` — the tag has to point at a commit whose
   `pubspec.yaml` already carries the new version, or the pipeline stops on its
   own version check.
7. **Tag**: `git tag vX.Y.Z && git push origin vX.Y.Z`. This starts the release
   workflow; everything below happens without further input.
8. **Verify each artifact launches** from the draft release, on a machine that
   did not build it — Gatekeeper, SmartScreen and the package managers only
   show their real behaviour on a clean host.
9. **Publish the draft** in the GitHub UI once the artifacts check out.

## Artifacts

`APP_NAME` and `DIST_DIR` come from `.env` (defaults `Mergelio` and `dist`).
`<arch>` is `arm64` or `x64`, taken from the build host.

| Platform | Command | Output |
| --- | --- | --- |
| macOS, ad-hoc signed | `make build-macos` | `dist/<APP_NAME>-<version>-macos-<arch>.zip` |
| macOS, Developer ID | `./scripts/build-macos-dmg.sh` | `dist/<APP_NAME>-<version>-macos-<arch>.dmg` and `-update.zip` |
| Linux, portable | `make build-linux` | `dist/<APP_NAME>-<version>-linux-<arch>.tar.gz` |
| Debian / Ubuntu | `make installer-linux` | `dist/mergelio_<version>_<debarch>.deb` |
| Fedora | `make installer-fedora` | `dist/mergelio-<version>-<release>.<dist>.<rpmarch>.rpm` |
| Windows | `make build-windows` | `dist/<APP_NAME>-<version>-windows-<arch>.zip` and `-setup.exe` |

The package formats name their own files: `_` separated with `amd64` for Debian,
`-` separated with `x86_64` for RPM. Both are canonical for their tooling.

The `build-*` scripts accept `CLEAN=1` (`flutter clean` first),
`SKIP_GEN=1` (skip code generation when the generated sources are current) and
`SKIP_PACKAGE=1` (build without producing an archive). Windows takes them as
PowerShell environment variables:

```powershell
$env:CLEAN = 1; .\scripts\build-windows-installer.ps1
```

Linux and Windows builds are unsigned and need no configuration.

### Installers

`make build-windows` also produces `…-setup.exe` via Inno Setup 6, which must
be installed (`winget install -e --id JRSoftware.InnoSetup`); set
`SKIP_INSTALLER=1` to build the zip alone. The installer writes to Program
Files, adds Start menu and optional desktop shortcuts, and registers an
uninstall entry.

`make installer-linux` builds a `.deb` with `dpkg-deb` (`sudo apt install
dpkg-dev`). It installs the app under `/opt/mergelio`, links
`/usr/bin/mergelio`, and registers the desktop entry, the icon and the AppStream
metadata so the app shows up in the launcher and in software centres.
`SKIP_BUILD=1` packages a bundle that is already built.

`make installer-fedora` builds the same layout as an `.rpm` with `rpmbuild`
(`sudo dnf install rpm-build`). Run it on Fedora, or in a `fedora:` container:
the package carries a `%{dist}` tag and resolves its dependencies against the
distribution it was built on. Set `RPM_SIGN_KEY` to a key in the local keyring
to sign the result; left empty the package is unsigned, which is all a local
install needs.

## Signing & notarization (macOS)

Signing is configured entirely through `.env` in the repository root. Copy the
template and fill in what you have:

```bash
cp .env.example .env
```

| Variable | Purpose |
| --- | --- |
| `MACOS_SIGN_IDENTITY` | Developer ID certificate name, as shown by `security find-identity -v -p codesigning` |
| `MACOS_TEAM_ID` | Apple Developer Team ID; derived from the certificate name when omitted |
| `MACOS_NOTARY_PROFILE` | `notarytool` keychain profile name, created once via `xcrun notarytool store-credentials` |

`.env` is gitignored and holds no credentials: the Apple ID and app-specific
password live in the macOS keychain behind the notary profile, and the private
key lives in the keychain behind the certificate. Only names are referenced.

`scripts/build-macos-dmg.sh` then builds, re-signs the bundle with clean entitlements,
validates the signature, packages a DMG, notarizes and staples it:

```bash
./scripts/build-macos-dmg.sh                   # version from pubspec.yaml
./scripts/build-macos-dmg.sh 1.4.2             # explicit version in the DMG name
SKIP_NOTARIZE=1 ./scripts/build-macos-dmg.sh   # stop after signing the .app
CLEAN=1 ./scripts/build-macos-dmg.sh           # flutter clean first
```

Each variable degrades gracefully. With `MACOS_NOTARY_PROFILE` empty you get a
signed but un-notarized DMG. With `MACOS_SIGN_IDENTITY` empty you get an ad-hoc
signed `.app` — enough to run locally, not enough to hand to someone else.

Alongside the DMG the script emits `…-macos-<arch>-update.zip`: the same bundle,
stapled and archived with `ditto`. The notarization ticket is keyed to the
code's cdhash rather than the container, so stapling the `.app` needs no second
notary submission, and the zip is what the in-app updater downloads — it
launches offline, without a Gatekeeper round trip.

## Release pipeline

`.github/workflows/release.yml` runs on every pushed `v*` tag, and can also be
started by hand from the Actions tab to exercise the build without tagging (no
release is drafted in that case — a GitHub release needs a tag to hang off).

| Job | Runner | Produces |
| --- | --- | --- |
| Gate | ubuntu-latest | version check, formatting, `flutter analyze`, tests |
| macOS (arm64) | macos-15 | signed, notarized `.dmg` and `-update.zip` |
| Windows (x64) | windows-2022 | `…-setup.exe` |
| Linux (x64) | ubuntu-22.04 | `.deb` |
| Fedora (x64) | `fedora:41` container | signed `.rpm` |
| Draft release | ubuntu-latest | `SHA256SUMS.txt`, its signature, the draft |

Ubuntu 22.04 rather than latest on purpose: its glibc 2.35 keeps the binary
usable on Debian 12 and older Ubuntu. Building on 24.04 would not.

The gate refuses a tag whose version disagrees with `pubspec.yaml`, since the
artifacts are named after `pubspec.yaml` while the release hangs off the tag.
Tags starting with `v0.0.0` are exempt: they exist to exercise the pipeline and
their draft is meant to be deleted afterwards.

The release is left as a **draft** deliberately. Nothing reaches users until
someone has looked at the artifacts and pressed publish.

### Publishing is what ships the update

Pressing publish is not only a visibility change. `.github/workflows/appcast.yml`
runs on `release: published`, builds `appcast.json` from that release's
`SHA256SUMS.txt`, signs it with `UPDATE_SIGNING_KEY`, and attaches both files to
the release. Installed copies of Mergelio read that manifest from
`releases/latest/download/appcast.json`, which does not resolve for a draft — so
a release that is never published is a release no existing install will ever be
offered.

Prereleases deliberately get no manifest. `releases/latest` skips them, so a
manifest there would advertise a build that stable users were never meant to
receive. To rehearse the flow against a release candidate, run the Appcast
workflow by hand with the tag as its input: that path is exempt from the
prerelease check and attaches a manifest to that one release without making it
the latest.

Losing `UPDATE_SIGNING_KEY` is not recoverable from the app side. Every
installed copy carries the matching public key and rejects a manifest signed by
anything else, so a new key means those installs stop accepting updates until
they are reinstalled by hand.

### Secrets

Most degrade on their own: the pipeline publishes something less trustworthy
and says so in the log. The macOS certificate is the exception — without it the
macOS job fails and no release is produced.

| Secret | Missing means |
| --- | --- |
| `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` | the macOS job fails; a release is never signed ad-hoc |
| `MACOS_APPLE_ID`, `MACOS_APP_PASSWORD`, `MACOS_TEAM_ID`, `MACOS_SIGN_IDENTITY` | needed alongside the certificate for notarization |
| `LINUX_GPG_PRIVATE_KEY`, `LINUX_GPG_PASSPHRASE` | an unsigned `.rpm` and unsigned checksums |
| `WINDOWS_SIGN_TOKEN` | an unsigned `setup.exe` — SmartScreen warns on first run |

`WINDOWS_SIGN_TOKEN` is a switch, not yet an implementation: setting it turns
on a two-pass signing branch whose signing steps are still placeholders and
fail on purpose. Leave it unset until a certificate has been chosen.

## Distribution

Artifacts are published by hand; the app has no updater and does not check for
new versions, so users pick up a release only by downloading it themselves.

Ad-hoc signed builds are the norm for anyone building from source without an
Apple Developer account. Gatekeeper blocks them on first launch on another
machine — open via right-click → Open, or clear the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/Mergelio.app
```

## Telemetry

Telemetry and crash reporting are **opt-in** (Preferences → General, off by
default) and no backend is wired up: `TelemetryReporter` writes to a sink
interface that has no HTTP implementation, so nothing leaves the machine today.
Should one ever be added, property values are already scrubbed of file paths,
emails, URLs and long tokens before they reach the sink.
