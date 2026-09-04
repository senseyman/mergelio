import 'dart:io';

import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/update/app_version.dart';
import 'package:mergelio/domain/update/update_decision.dart';
import 'package:mergelio/domain/update/update_manifest.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/update_controller.dart';

UpdateManifest manifestFor(String version) {
  final parsed = AppVersion.parse(version);
  return UpdateManifest(
    schema: 1,
    version: '${parsed.semver}',
    build: parsed.build,
    notesUrl: 'https://example.invalid/notes',
    artifacts: const {
      'macos-arm64': UpdateArtifact(
        url: 'https://example.invalid/app.zip',
        sha256: 'abc',
        size: 1,
      ),
    },
  );
}

UpdateAvailable _available(String version) {
  final m = manifestFor(version);
  return UpdateAvailable(m, m.artifacts['macos-arm64']);
}

UpdateStatus foundStatus(String version) => UpdateFound(_available(version));

UpdateStatus readyStatus(String version) =>
    UpdateReady(_available(version), File('/tmp/app.zip'));

/// A controller wired entirely to in-memory doubles, parked in [initial].
UpdateController fakeUpdateController(
  UpdateStatus initial, {
  AppSettings settings = const AppSettings(updateConsent: 'on'),
  bool busy = false,
  List<String>? installed,
}) {
  final controller = UpdateController(
    settings: SettingsController(InMemorySettingsRepository(), settings),
    fetchManifest: () async => manifestFor('1.5.0+16'),
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
  controller.debugSetStatus(initial);
  return controller;
}
