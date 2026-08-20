# Releasing Mergelio

Mergelio follows [Semantic Versioning](https://semver.org). The version lives in
`pubspec.yaml` as `version: <semver>+<build>` (e.g. `1.4.0+14`).

There is no release automation. Every artifact is built by hand on a host of the
matching platform — the build scripts refuse to cross-compile, and Apple signing
needs a real keychain anyway.

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
6. **Build the artifacts** — once per platform, on that platform (below).
7. **Verify each artifact launches** from a clean unzip on a machine that did
   not build it.
8. **Tag**: `git tag vX.Y.Z && git push origin vX.Y.Z`. Nothing is triggered by
   the tag; publishing the artifacts is a manual step.

## Artifacts

`APP_NAME` and `DIST_DIR` come from `.env` (defaults `Mergelio` and `dist`).
`<arch>` is `arm64` or `x64`, taken from the build host.

| Platform | Command | Output |
| --- | --- | --- |
| macOS, ad-hoc signed | `make build-macos` | `dist/<APP_NAME>-<version>-macos-<arch>.zip` |
| macOS, Developer ID | `./scripts/build-macos-dmg.sh` | `dist/<APP_NAME>-<version>.dmg` |
| Linux, portable | `make build-linux` | `dist/<APP_NAME>-<version>-linux-<arch>.tar.gz` |
| Linux, installer | `make installer-linux` | `dist/mergelio_<version>_<debarch>.deb` |
| Windows | `make build-windows` | `dist/<APP_NAME>-<version>-windows-<arch>.zip` and `-setup.exe` |

The three `build-*` scripts accept `CLEAN=1` (`flutter clean` first),
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
`/usr/bin/mergelio`, and registers the desktop entry and icon so the app shows
up in the launcher. `SKIP_BUILD=1` packages a bundle that is already built.

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

## Distribution

Artifacts are published by hand; the app has no updater and does not check for
new versions, so users pick up a release only by downloading it themselves.

Ad-hoc signed builds are the norm for anyone building from source without an
Apple Developer account. Gatekeeper blocks them on first launch on another
machine — open via right-click → Open, or clear the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/mergelio.app
```

## Telemetry

Telemetry and crash reporting are **opt-in** (Preferences → General, off by
default) and no backend is wired up: `TelemetryReporter` writes to a sink
interface that has no HTTP implementation, so nothing leaves the machine today.
Should one ever be added, property values are already scrubbed of file paths,
emails, URLs and long tokens before they reach the sink.
