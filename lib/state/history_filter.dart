import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/git_service.dart';
import '../domain/search.dart';
import 'repo_data.dart';

/// Identifies one author/date filter inside one repository, so the history is
/// walked once per (repo, author, range) rather than once per rebuild.
class HistoryFilterKey {
  final String repoPath;
  final String author;
  final DateTime? since;
  final DateTime? until;

  /// Leave merge commits out, so they do not count as matches waiting in
  /// older history when the graph is hiding them anyway.
  final bool noMerges;

  /// [historyStamp] of the history the filter is answering for. Not read by
  /// the walk: it is here so a moved ref makes a new key, and the filter is
  /// asked again instead of keeping the shas of the history it saw before.
  final String stamp;
  const HistoryFilterKey(
    this.repoPath,
    this.author, {
    this.since,
    this.until,
    this.noMerges = false,
    this.stamp = '',
  });

  @override
  bool operator ==(Object other) =>
      other is HistoryFilterKey &&
      other.repoPath == repoPath &&
      other.author == author &&
      other.since == since &&
      other.until == until &&
      other.noMerges == noMerges &&
      other.stamp == stamp;

  @override
  int get hashCode =>
      Object.hash(repoPath, author, since, until, noMerges, stamp);

  @override
  String toString() =>
      'HistoryFilterKey($repoPath, $author, $since, $until, '
      'noMerges: $noMerges)';
}

/// Fingerprint of the refs [data]'s history was walked from: every branch,
/// remote branch and stash tip, and the tag names. A commit, fetch, rebase
/// or new stash changes it; paging in more history or editing files does not.
String historyStamp(RepoData data) => [
  for (final b in data.branches) '${b.name}=${b.tip}',
  for (final r in data.remoteBranches) '${r.name}=${r.tip}',
  for (final s in data.stashes) s.sha,
  ...data.tags,
].join('\n');

/// Shas of every commit, on any branch, whose author matches
/// [HistoryFilterKey.author] — name or email — and that was authored within
/// the date range. Read from git so the filter reaches past the loaded page.
/// Stashes count the way the graph draws them: every entry, never their
/// internal index and untracked snapshots.
///
/// Auto-disposed: every author that survives the search bar's debounce is a
/// new key, and keeping each one alive would grow the cache for as long as the
/// repo stays open.
///
/// A failed read yields no shas: the graph then shows no matches, rather than
/// pretending the filter is off and highlighting the whole history.
final historyFilterProvider = FutureProvider.autoDispose
    .family<Set<String>, HistoryFilterKey>((ref, key) async {
      if (key.author.trim().isEmpty && key.since == null && key.until == null) {
        return const {};
      }
      final git = ref.watch(gitServiceProvider);
      // Each author that survives the debounce is a new key, and the previous
      // walk would otherwise run on to its timeout for nobody.
      final cancel = GitCancel();
      ref.onDispose(cancel.cancel);
      try {
        final (:stashShas, :auxShas) = await GitReader(
          git,
          key.repoPath,
        ).stashWalk();
        // A walk over every branch of a large repo outlasts the default guard.
        final r = await git.run(
          historyFilterArgs(
            key.author,
            key.since,
            noMerges: key.noMerges,
            stashes: stashShas,
          ),
          repoPath: key.repoPath,
          timeout: const Duration(minutes: 2),
          // `-i` folds non-ASCII letters only in a UTF-8 locale, and an app
          // started from the Dock or Finder may inherit none.
          environment: const {'LC_ALL': 'C.UTF-8'},
          cancel: cancel,
        );
        if (!r.ok) return const {};
        final shas = <String>{};
        for (final line in r.stdout.split('\n')) {
          final f = line.split('\x00');
          if (f.length != 2 || auxShas.contains(f[0])) continue;
          final secs = int.tryParse(f[1]);
          if (secs == null) continue;
          final authored = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
          if (authoredWithin(authored, key.since, key.until)) shas.add(f[0]);
        }
        return shas;
      } on Object {
        return const {};
      }
    });
