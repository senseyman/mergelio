import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/models.dart';
import 'diff_target.dart';
import 'repo_data.dart';

/// Display form of a revision: a full sha shortens, everything else — branch,
/// tag, `origin/main` — shows as written, because the name is what the user
/// picked.
String compareRefLabel(String rev) =>
    isFullSha(rev) ? rev.substring(0, 7) : rev;

/// A revision written as a full object name. Such a side of a comparison is a
/// fixed tree — unlike a branch or tag, nothing the user does moves it.
bool isFullSha(String rev) => rev.length == 40 && _hex.hasMatch(rev);

final _hex = RegExp(r'^[0-9a-f]+$');

/// Two revisions being compared, read [from] → [to]: the file list and diffs
/// describe what it takes to get from the first to the second.
class CompareTarget {
  final String repoPath;
  final String from;
  final String to;
  const CompareTarget({
    required this.repoPath,
    required this.from,
    required this.to,
  });

  String get fromLabel => compareRefLabel(from);
  String get toLabel => compareRefLabel(to);

  /// The same pair read in the other direction.
  CompareTarget get swapped =>
      CompareTarget(repoPath: repoPath, from: to, to: from);

  /// One file of this comparison, as a read-only diff for the sheet.
  /// [origPath] is the name the file had on the [from] side of a rename.
  DiffTarget fileTarget(String path, {String? origPath}) => DiffTarget(
    repoPath: repoPath,
    path: path,
    baseRev: from,
    commitSha: to,
    origPath: origPath,
  );

  @override
  bool operator ==(Object other) =>
      other is CompareTarget &&
      other.repoPath == repoPath &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(repoPath, from, to);
}

/// A revision marked as the left side of a comparison that is still waiting
/// for its right side. Carries the repository it was marked in: a mark left
/// behind in another tab means nothing here.
class CompareMark {
  final String repoPath;
  final String sha;
  const CompareMark({required this.repoPath, required this.sha});

  @override
  bool operator ==(Object other) =>
      other is CompareMark && other.repoPath == repoPath && other.sha == sha;

  @override
  int get hashCode => Object.hash(repoPath, sha);
}

/// The armed mark, or null when none is.
final compareMarkProvider = StateProvider<CompareMark?>((_) => null);

/// The comparison the right panel shows, or null when it shows the selected
/// commit instead.
final compareTargetProvider = StateProvider<CompareTarget?>((_) => null);

/// Re-reads the calling provider when a ref either side of a comparison names
/// could have moved.
///
/// A side written as a ref moves under the user as they commit, merge or
/// fetch, so anything derived from it has to follow. Only what the refs point
/// at can change the answer: a two-dot comparison reads committed trees, so
/// working-tree edits — the bulk of what a refresh reports — leave it alone,
/// and two object names cannot go stale at all. Listening rather than watching
/// also avoids a second read on every open, for the loading→data step that
/// changes nothing here.
void followRefMoves(
  Ref ref, {
  required String repoPath,
  required String from,
  required String to,
}) {
  if (isFullSha(from) && isFullSha(to)) return;
  ref.listen(repoDataProvider(repoPath), (prev, next) {
    final before = prev?.valueOrNull;
    final after = next.valueOrNull;
    if (before == null || after == null) return;
    if (!listEquals(before.branches, after.branches) ||
        !listEquals(before.remoteBranches, after.remoteBranches) ||
        !listEquals(before.tags, after.tags)) {
      ref.invalidateSelf();
    }
  });
}

/// Files that differ between the two sides of a comparison.
final compareFilesProvider = FutureProvider.family
    .autoDispose<List<CommitFileChange>, CompareTarget>((ref, target) async {
      followRefMoves(
        ref,
        repoPath: target.repoPath,
        from: target.from,
        to: target.to,
      );
      final reader = GitReader(ref.watch(gitServiceProvider), target.repoPath);
      return reader.compareFiles(target.from, target.to);
    });
