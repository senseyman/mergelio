// The analyzer rejects JsonKey on a constructor parameter, but freezed forwards
// it to the generated field where it is valid.
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'app_version.dart';

part 'update_manifest.freezed.dart';
part 'update_manifest.g.dart';

/// Manifest layouts this build knows how to read. A future release can add
/// fields freely; bumping this number is for changes that would make an older
/// client misread the file, and an older client then declines the update
/// rather than guessing.
const int kSupportedManifestSchema = 1;

@freezed
class UpdateArtifact with _$UpdateArtifact {
  const factory UpdateArtifact({
    required String url,
    required String sha256,
    required int size,
  }) = _UpdateArtifact;

  factory UpdateArtifact.fromJson(Map<String, dynamic> json) =>
      _$UpdateArtifactFromJson(json);
}

@freezed
class UpdateManifest with _$UpdateManifest {
  const UpdateManifest._();

  const factory UpdateManifest({
    required int schema,
    required String version,
    @Default(0) int build,
    DateTime? published,
    @JsonKey(name: 'notes_url') required String notesUrl,
    @Default(<String, UpdateArtifact>{}) Map<String, UpdateArtifact> artifacts,
  }) = _UpdateManifest;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) =>
      _$UpdateManifestFromJson(json);

  AppVersion get appVersion => AppVersion.parse('$version+$build');
}
