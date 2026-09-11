import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the diff bottom sheet shows. [commitSha] null means the working tree
/// (editable, staging gutter enabled); non-null means a read-only commit diff.
/// [baseRev] set alongside it turns that into a comparison of two revisions,
/// [baseRev] → [commitSha], which is read-only too. [staged] selects which side
/// of a working-tree file to show: true = staged (index vs HEAD), false =
/// unstaged (working tree vs index). Ignored for commit diffs. [wholeFile]
/// widens the diff to every line of the file instead of just the changed
/// regions. [origPath] names where a renamed file came from, so the diff can
/// be asked for both of its names.
class DiffTarget {
  final String repoPath;
  final String path;
  final String? commitSha;
  final String? baseRev;
  final String? origPath;
  final bool staged;
  final bool wholeFile;
  const DiffTarget({
    required this.repoPath,
    required this.path,
    this.commitSha,
    this.baseRev,
    this.origPath,
    this.staged = false,
    this.wholeFile = false,
  });

  bool get isWorkingTree => commitSha == null;

  /// Two revisions side by side rather than one commit against its parent.
  bool get isComparison => commitSha != null && baseRev != null;

  /// The same target viewed from the other staging side.
  DiffTarget withStaged(bool staged) => DiffTarget(
    repoPath: repoPath,
    path: path,
    commitSha: commitSha,
    baseRev: baseRev,
    origPath: origPath,
    staged: staged,
    wholeFile: wholeFile,
  );

  /// The same target shown as the whole file, or only its changed regions.
  DiffTarget withWholeFile(bool wholeFile) => DiffTarget(
    repoPath: repoPath,
    path: path,
    commitSha: commitSha,
    baseRev: baseRev,
    origPath: origPath,
    staged: staged,
    wholeFile: wholeFile,
  );

  @override
  bool operator ==(Object other) =>
      other is DiffTarget &&
      other.repoPath == repoPath &&
      other.path == path &&
      other.commitSha == commitSha &&
      other.baseRev == baseRev &&
      other.origPath == origPath &&
      other.staged == staged &&
      other.wholeFile == wholeFile;

  @override
  int get hashCode => Object.hash(
    repoPath,
    path,
    commitSha,
    baseRev,
    origPath,
    staged,
    wholeFile,
  );
}

/// The file currently open in the diff sheet, or null when it is closed.
final diffTargetProvider = StateProvider<DiffTarget?>((_) => null);
