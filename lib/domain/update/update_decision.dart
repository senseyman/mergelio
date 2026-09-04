import 'app_version.dart';
import 'update_manifest.dart';

/// What the app should do about a manifest it just read.
sealed class UpdateDecision {
  const UpdateDecision();
}

/// Nothing newer is published, or what is published is older.
class UpToDate extends UpdateDecision {
  const UpToDate();
}

/// A newer release the user has already dismissed. Dismissal is per version, so
/// the release after it is offered again.
class UpdateSkipped extends UpdateDecision {
  final AppVersion version;
  const UpdateSkipped(this.version);
}

/// A manifest written for a layout this build does not understand. Declining is
/// the safe answer: a misread manifest points at the wrong download.
class ManifestUnsupported extends UpdateDecision {
  final int schema;
  const ManifestUnsupported(this.schema);
}

/// A newer release. [artifact] is null when the manifest carries no build for
/// this platform - the app says so and links the release page instead.
class UpdateAvailable extends UpdateDecision {
  final UpdateManifest manifest;
  final UpdateArtifact? artifact;
  const UpdateAvailable(this.manifest, this.artifact);

  bool get canInstall => artifact != null;
  AppVersion get version => manifest.appVersion;
}

UpdateDecision decideUpdate({
  required UpdateManifest manifest,
  required AppVersion current,
  required String? platformKey,
  String skippedVersion = '',
}) {
  if (manifest.schema > kSupportedManifestSchema) {
    return ManifestUnsupported(manifest.schema);
  }

  final offered = manifest.appVersion;
  if (offered <= current) return const UpToDate();

  if (skippedVersion.isNotEmpty &&
      AppVersion.tryParse(skippedVersion) == offered) {
    return UpdateSkipped(offered);
  }

  final artifact = platformKey == null ? null : manifest.artifacts[platformKey];
  return UpdateAvailable(manifest, artifact);
}
