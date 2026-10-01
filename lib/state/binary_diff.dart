import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/blob.dart';
import '../domain/git/diff.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_service.dart';
import '../domain/git/models.dart';
import 'diff_target.dart';

typedef BinarySides = ({BlobRef? before, BlobRef? after});

/// Where the two sides of [file]'s binary diff live. [staged] is the side the
/// loaded document shows, which can differ from what the target asked for.
/// A side the change has no content on — before an add, after a delete — is
/// null.
BinarySides binarySidesFor(
  DiffTarget target,
  FileDiff file, {
  required bool staged,
}) {
  final oldPath = file.oldPath ?? target.origPath ?? file.path;
  final added = file.status == GitChange.added;
  final deleted = file.status == GitChange.deleted;

  final BlobRef before, after;
  if (target.commitSha != null) {
    // First parent, matching the text diff's `--first-parent`.
    before = RevisionBlob(target.baseRev ?? '${target.commitSha}^', oldPath);
    after = RevisionBlob(target.commitSha!, file.path);
  } else if (staged) {
    before = RevisionBlob('HEAD', oldPath);
    after = IndexBlob(file.path);
  } else {
    before = IndexBlob(oldPath);
    after = WorktreeBlob(file.path);
  }
  return (before: added ? null : before, after: deleted ? null : after);
}

/// Mine and theirs for a conflicted path, as the index's stages 2 and 3. A
/// side that deleted the path has no stage to read.
BinarySides conflictSidesFor(
  String path, {
  bool hasOurs = true,
  bool hasTheirs = true,
}) => (
  before: hasOurs ? IndexBlob(path, stage: 2) : null,
  after: hasTheirs ? IndexBlob(path, stage: 3) : null,
);

/// One side to load. [version] ties a side that can change under the app —
/// the index, the file on disk — to the diff it was asked for, so a reloaded
/// diff reads it afresh instead of showing the cached bytes.
class BlobRequest {
  final String repoPath;
  final BlobRef ref;
  final Object? version;
  const BlobRequest({required this.repoPath, required this.ref, this.version});

  @override
  bool operator ==(Object other) =>
      other is BlobRequest &&
      other.repoPath == repoPath &&
      other.ref == ref &&
      identical(other.version, version);

  @override
  int get hashCode => Object.hash(repoPath, ref, identityHashCode(version));
}

/// The bytes of one binary-diff side, capped at [blobPreviewMaxBytes]; null
/// when the side does not exist. Fails when the engine has no way to hand
/// back raw bytes.
final blobProvider = FutureProvider.autoDispose.family<BlobLoad?, BlobRequest>((
  ref,
  req,
) {
  final git = ref.watch(gitServiceProvider);
  if (git is! GitBytesRunner) {
    throw UnsupportedError('the git engine cannot read raw bytes');
  }
  return BlobReader(
    git: git,
    bytes: git as GitBytesRunner,
    repoPath: req.repoPath,
  ).read(req.ref);
});
