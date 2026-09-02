import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/update/app_version.dart';
import 'package:mergelio/domain/update/update_manifest.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/update_controller.dart';

final _manifest = UpdateManifest(
  schema: 1,
  version: '1.5.0',
  build: 16,
  notesUrl: 'https://example.invalid/notes',
  artifacts: const {
    'macos-arm64': UpdateArtifact(
      url: 'https://example.invalid/app.zip',
      sha256: 'abc',
      size: 1,
    ),
  },
);

UpdateController _controller({
  AppSettings settings = const AppSettings(updateConsent: 'on'),
  Future<UpdateManifest> Function()? fetch,
  bool busy = false,
  List<String>? installed,
}) {
  return UpdateController(
    settings: SettingsController(InMemorySettingsRepository(), settings),
    fetchManifest: fetch ?? () async => _manifest,
    currentVersion: () async => AppVersion.parse('1.4.1+15'),
    platformKey: () async => 'macos-arm64',
    downloadArtifact: (artifact, onProgress) async {
      onProgress(1, 1);
      return File('/tmp/app.zip');
    },
    handOff: (file) async => installed?.add(file.path),
    canInstallInPlace: true,
    isBusy: () => busy,
    exitApp: () {},
  );
}

void main() {
  test('finds a newer release', () async {
    final c = _controller();
    await c.check(manual: true);
    expect(c.state, isA<UpdateFound>());
    expect((c.state as UpdateFound).version, AppVersion.parse('1.5.0+16'));
  });

  test('stays silent while consent has not been given', () async {
    final c = _controller(settings: const AppSettings());
    await c.check();
    expect(c.state, isA<UpdateIdle>());
  });

  test('a manual check ignores the consent gate', () async {
    final c = _controller(settings: const AppSettings());
    await c.check(manual: true);
    expect(c.state, isA<UpdateFound>());
  });

  test('does not re-check within the throttle window', () async {
    var calls = 0;
    final c = _controller(
      settings: AppSettings(
        updateConsent: 'on',
        updateLastCheckMs: DateTime.now().millisecondsSinceEpoch,
      ),
      fetch: () async {
        calls++;
        return _manifest;
      },
    );
    await c.check();
    expect(calls, 0);
  });

  test('reports a failure instead of throwing', () async {
    final c = _controller(fetch: () async => throw const SocketException('no'));
    await c.check(manual: true);
    expect(c.state, isA<UpdateFailed>());
  });

  test('skipping a version silences it and clears the state', () async {
    final c = _controller();
    await c.check(manual: true);
    c.skip();
    expect(c.state, isA<UpdateIdle>());

    await c.check(manual: true);
    expect(c.state, isA<UpdateIdle>());
  });

  test('refuses to install while a git operation is running', () async {
    final installed = <String>[];
    final c = _controller(busy: true, installed: installed);
    await c.check(manual: true);
    await c.download();
    await c.install();
    expect(installed, isEmpty);
    expect(c.state, isA<UpdateReady>());
  });

  test('hands the verified file to the installer once idle', () async {
    final installed = <String>[];
    final c = _controller(installed: installed);
    await c.check(manual: true);
    await c.download();
    expect(c.state, isA<UpdateReady>());
    await c.install();
    expect(installed, ['/tmp/app.zip']);
  });
}
