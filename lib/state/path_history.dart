import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';

/// Identifies one path inside one repository, so the history read is cached per
/// file rather than per call.
class PathKey {
  final String repoPath;

  /// Repo-relative, `/`-separated.
  final String path;
  const PathKey(this.repoPath, this.path);

  @override
  bool operator ==(Object other) =>
      other is PathKey && other.repoPath == repoPath && other.path == path;

  @override
  int get hashCode => Object.hash(repoPath, path);

  @override
  String toString() => 'PathKey($repoPath, $path)';
}

/// Shas of every commit that touched [PathKey.path], following the file across
/// renames. A commit carries no file list, so which ones touched a path can
/// only come from git.
///
/// A failed read yields no shas: the graph then shows no matches, rather than
/// pretending the filter is off and highlighting the whole history.
final pathHistoryProvider = FutureProvider.family<Set<String>, PathKey>((
  ref,
  key,
) async {
  if (key.path.isEmpty) return const {};
  final git = ref.watch(gitServiceProvider);
  final r = await git.run([
    'log',
    '--pretty=format:%H',
    '--follow',
    // Everything after `--` is a path; without it a file named like a branch
    // would be read as a revision.
    '--',
    key.path,
  ], repoPath: key.repoPath);
  if (!r.ok) return const {};
  return r.stdout.split('\n').where((s) => s.isNotEmpty).toSet();
});
