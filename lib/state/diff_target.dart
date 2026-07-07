import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the diff bottom sheet shows. [commitSha] null means the working tree
/// (editable, staging gutter enabled); non-null means a read-only commit diff.
class DiffTarget {
  final String repoPath;
  final String path;
  final String? commitSha;
  const DiffTarget({
    required this.repoPath,
    required this.path,
    this.commitSha,
  });

  bool get isWorkingTree => commitSha == null;

  @override
  bool operator ==(Object other) =>
      other is DiffTarget &&
      other.repoPath == repoPath &&
      other.path == path &&
      other.commitSha == commitSha;

  @override
  int get hashCode => Object.hash(repoPath, path, commitSha);
}

/// The file currently open in the diff sheet, or null when it is closed.
final diffTargetProvider = StateProvider<DiffTarget?>((_) => null);
