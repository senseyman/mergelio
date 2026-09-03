import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/update/appcast_client.dart';
import '../data/update/host_info.dart';
import '../data/update/installer_factory.dart';
import '../data/update/update_downloader.dart';
import '../domain/update/app_version.dart';
import '../domain/update/update_decision.dart';
import '../domain/update/update_manifest.dart';
import 'feedback.dart';
import 'settings_controller.dart';

/// No newer release is on offer, or the user dismissed the one that was.
sealed class UpdateStatus {
  const UpdateStatus();
}

class UpdateIdle extends UpdateStatus {
  const UpdateIdle();
}

class UpdateChecking extends UpdateStatus {
  const UpdateChecking();
}

/// The check ran and this build is current. Distinct from [UpdateIdle] so a
/// manual check can say so instead of appearing to do nothing.
class UpdateNone extends UpdateStatus {
  const UpdateNone();
}

class UpdateFound extends UpdateStatus {
  final UpdateAvailable available;
  const UpdateFound(this.available);
  AppVersion get version => available.version;
  UpdateManifest get manifest => available.manifest;
}

class UpdateDownloading extends UpdateStatus {
  final UpdateAvailable available;
  final double progress;
  const UpdateDownloading(this.available, this.progress);
}

class UpdateReady extends UpdateStatus {
  final UpdateAvailable available;
  final File artifact;
  const UpdateReady(this.available, this.artifact);
}

class UpdateFailed extends UpdateStatus {
  final String message;
  const UpdateFailed(this.message);
}

typedef ProgressCallback = void Function(int received, int total);

/// How long a completed check stays good for. Automatic checks respect it; a
/// check the user asked for does not.
const Duration kUpdateCheckInterval = Duration(hours: 24);

class UpdateController extends StateNotifier<UpdateStatus> {
  // Injected rather than read off a Ref, so the whole controller is testable
  // with plain callbacks: no ProviderContainer and no network.
  final SettingsController settings;
  final Future<UpdateManifest> Function() fetchManifest;
  final Future<AppVersion> Function() currentVersion;
  final Future<String?> Function() platformKey;
  final Future<File> Function(UpdateArtifact, ProgressCallback)
  downloadArtifact;
  final Future<void> Function(File) handOff;
  final bool Function() isBusy;
  final void Function() exitApp;

  final bool canInstallInPlace;

  UpdateController({
    required this.settings,
    required this.fetchManifest,
    required this.currentVersion,
    required this.platformKey,
    required this.downloadArtifact,
    required this.handOff,
    required this.canInstallInPlace,
    required this.isBusy,
    required this.exitApp,
  }) : super(const UpdateIdle());

  Future<void> check({bool manual = false}) async {
    if (!manual) {
      if (settings.state.updateConsent != 'on') return;
      final last = DateTime.fromMillisecondsSinceEpoch(
        settings.state.updateLastCheckMs,
      );
      if (DateTime.now().difference(last) < kUpdateCheckInterval) return;
    }

    state = const UpdateChecking();
    try {
      final manifest = await fetchManifest();
      settings.setUpdateLastCheck(DateTime.now());

      final decision = decideUpdate(
        manifest: manifest,
        current: await currentVersion(),
        platformKey: await platformKey(),
        skippedVersion: settings.state.updateSkippedVersion,
      );

      state = switch (decision) {
        UpdateAvailable a => UpdateFound(a),
        UpToDate() => manual ? const UpdateNone() : const UpdateIdle(),
        UpdateSkipped() => const UpdateIdle(),
        ManifestUnsupported() => const UpdateIdle(),
      };
    } catch (e) {
      debugPrint('update: check failed: $e');
      state = UpdateFailed('$e');
    }
  }

  Future<void> download() async {
    final found = state;
    if (found is! UpdateFound) return;
    final artifact = found.available.artifact;
    if (artifact == null) return;

    state = UpdateDownloading(found.available, 0);
    try {
      final file = await downloadArtifact(artifact, (received, total) {
        if (total > 0) {
          state = UpdateDownloading(found.available, received / total);
        }
      });
      state = UpdateReady(found.available, file);
    } catch (e) {
      debugPrint('update: download failed: $e');
      state = UpdateFailed('$e');
    }
  }

  /// Hands the verified artifact to the platform installer and quits.
  ///
  /// A running Git operation blocks this: an installer that closes the app
  /// mid-rebase would leave the repository in a state the user never chose. The
  /// download stays ready, and the user can install once the operation ends.
  Future<void> install() async {
    final ready = state;
    if (ready is! UpdateReady || !canInstallInPlace) return;
    if (isBusy()) return;

    try {
      await handOff(ready.artifact);
      exitApp();
    } catch (e) {
      debugPrint('update: install failed: $e');
      state = UpdateFailed('$e');
    }
  }

  /// Silences this release for good. The next one is offered again.
  void skip() {
    final s = state;
    final version = switch (s) {
      UpdateFound f => f.version,
      UpdateDownloading d => d.available.version,
      UpdateReady r => r.available.version,
      _ => null,
    };
    if (version != null) {
      settings.setUpdateSkippedVersion(version.toString());
    }
    state = const UpdateIdle();
  }

  /// Hides the banner for this session without silencing the release.
  void dismiss() => state = const UpdateIdle();

  /// StateNotifier.state is protected, so parking a widget test on a given
  /// status needs an explicit way in.
  @visibleForTesting
  void debugSetStatus(UpdateStatus status) => state = status;
}

final updateStatusProvider =
    StateNotifierProvider<UpdateController, UpdateStatus>((ref) {
      final client = AppcastClient();
      final downloader = UpdateDownloader();
      final installer = installerForHost();
      return UpdateController(
        settings: ref.read(settingsProvider.notifier),
        fetchManifest: client.fetch,
        currentVersion: currentAppVersion,
        platformKey: currentPlatformKey,
        downloadArtifact: (artifact, onProgress) async {
          final dir = await Directory.systemTemp.createTemp('mergelio-update');
          return downloader.download(
            artifact,
            into: dir,
            onProgress: onProgress,
          );
        },
        handOff: installer.handOff,
        canInstallInPlace: installer.canInstallInPlace,
        isBusy: () => ref.read(busyProvider) != null,
        exitApp: () => exit(0),
      );
    });
