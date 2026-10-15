import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/search.dart';

/// Identifies one author/date filter inside one repository, so the history is
/// walked once per (repo, author, range) rather than once per rebuild.
class HistoryFilterKey {
  final String repoPath;
  final String author;
  final DateTime? since;
  final DateTime? until;
  const HistoryFilterKey(this.repoPath, this.author, {this.since, this.until});

  @override
  bool operator ==(Object other) =>
      other is HistoryFilterKey &&
      other.repoPath == repoPath &&
      other.author == author &&
      other.since == since &&
      other.until == until;

  @override
  int get hashCode => Object.hash(repoPath, author, since, until);

  @override
  String toString() => 'HistoryFilterKey($repoPath, $author, $since, $until)';
}

/// Shas of every commit, on any branch, whose author matches
/// [HistoryFilterKey.author] — name or email — and that was authored within
/// the date range. Read from git so the filter reaches past the loaded page.
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
      try {
        // A walk over every branch of a large repo outlasts the default guard.
        final r = await git.run(
          historyFilterArgs(key.author, key.since),
          repoPath: key.repoPath,
          timeout: const Duration(minutes: 2),
        );
        if (!r.ok) return const {};
        final shas = <String>{};
        for (final line in r.stdout.split('\n')) {
          final f = line.split('\x00');
          if (f.length != 2) continue;
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
