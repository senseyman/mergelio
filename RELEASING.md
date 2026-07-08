# Releasing Mergelio

Mergelio follows [Semantic Versioning](https://semver.org). The version lives in
`pubspec.yaml` as `version: <semver>+<build>` (e.g. `1.0.0+1`).

## Checklist

1. **Green main** — `flutter analyze` clean and `flutter test` all pass on CI.
2. **Bump the version** in `pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`).
3. **Update `CHANGELOG.md`** — move `Unreleased` entries under the new version
   with the date; add fresh compare links.
4. **Regenerate icons** if the brand master changed:
   `dart run flutter_launcher_icons`.
5. **Localization** — confirm `flutter gen-l10n` is up to date and no ARB keys
   are missing a translation.
6. **Tag & push**: `git tag vX.Y.Z && git push origin vX.Y.Z`.
   This triggers `.github/workflows/release.yml`, which builds and packages
   macOS (`.dmg`), Windows (`.zip`), and Linux (`.tar.gz`) and drafts a GitHub
   release with the artifacts attached.
7. **Review the draft release**, verify each installer launches, then publish.

## Signing & notarization

The release workflow produces **unsigned** artifacts unless the signing secrets
are configured in the repository:

| Secret | Purpose |
| --- | --- |
| `MACOS_CERT_P12`, `MACOS_NOTARY_USER`, `MACOS_NOTARY_PASSWORD` | macOS Developer ID signing + notarization |
| `WINDOWS_CERT_PFX` | Authenticode signing of the Windows build |

When present, the workflow's signing steps run automatically. Without them, the
build still succeeds and yields unsigned binaries suitable for testing.

## Auto-update

Auto-update is delivered by pointing the app's updater feed at the GitHub
Releases of this repository. Publishing a signed release makes it available to
clients on the stable channel.

## Telemetry

Telemetry and crash reporting are **opt-in** (Preferences → General, off by
default). No usage data leaves the machine unless the user enables it, and even
then values are scrubbed of paths, emails, URLs, and tokens before sending.
