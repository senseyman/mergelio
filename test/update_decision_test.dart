import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/update/app_version.dart';
import 'package:mergelio/domain/update/update_decision.dart';
import 'package:mergelio/domain/update/update_manifest.dart';

UpdateManifest _manifest({
  String version = '1.5.0',
  int build = 16,
  int schema = 1,
}) => UpdateManifest(
  schema: schema,
  version: version,
  build: build,
  notesUrl: 'https://example.invalid/notes',
  artifacts: const {
    'macos-arm64': UpdateArtifact(
      url: 'https://example.invalid/app.zip',
      sha256: 'abc',
      size: 1,
    ),
  },
);

void main() {
  test('offers a newer release', () {
    final d = decideUpdate(
      manifest: _manifest(),
      current: AppVersion.parse('1.4.1+15'),
      platformKey: 'macos-arm64',
    );
    expect(d, isA<UpdateAvailable>());
    expect((d as UpdateAvailable).canInstall, isTrue);
  });

  test('never offers a downgrade', () {
    final d = decideUpdate(
      manifest: _manifest(version: '1.3.0', build: 9),
      current: AppVersion.parse('1.4.1+15'),
      platformKey: 'macos-arm64',
    );
    expect(d, isA<UpToDate>());
  });

  test('treats the same version as up to date', () {
    final d = decideUpdate(
      manifest: _manifest(version: '1.4.1', build: 15),
      current: AppVersion.parse('1.4.1+15'),
      platformKey: 'macos-arm64',
    );
    expect(d, isA<UpToDate>());
  });

  test('honours a version the user chose to skip', () {
    final d = decideUpdate(
      manifest: _manifest(),
      current: AppVersion.parse('1.4.1+15'),
      platformKey: 'macos-arm64',
      skippedVersion: '1.5.0+16',
    );
    expect(d, isA<UpdateSkipped>());
  });

  test('a skip does not carry over to the next release', () {
    final d = decideUpdate(
      manifest: _manifest(version: '1.6.0', build: 17),
      current: AppVersion.parse('1.4.1+15'),
      platformKey: 'macos-arm64',
      skippedVersion: '1.5.0+16',
    );
    expect(d, isA<UpdateAvailable>());
  });

  test('announces an update it cannot install for this platform', () {
    final d = decideUpdate(
      manifest: _manifest(),
      current: AppVersion.parse('1.4.1+15'),
      platformKey: 'linux-x64-deb',
    );
    expect(d, isA<UpdateAvailable>());
    expect((d as UpdateAvailable).canInstall, isFalse);
    expect(d.artifact, isNull);
  });

  test('declines a manifest from the future', () {
    final d = decideUpdate(
      manifest: _manifest(schema: 2),
      current: AppVersion.parse('1.4.1+15'),
      platformKey: 'macos-arm64',
    );
    expect(d, isA<ManifestUnsupported>());
  });
}
