import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/search.dart';

/// Identifies one content search inside one repository, so the pickaxe is run
/// once per (repo, string, mode) rather than once per rebuild.
class ContentKey {
  final String repoPath;

  /// The string, or the regular expression when [mode] is
  /// [ContentSearchMode.diffText].
  final String text;
  final ContentSearchMode mode;
  const ContentKey(
    this.repoPath,
    this.text, [
    this.mode = ContentSearchMode.occurrences,
  ]);

  @override
  bool operator ==(Object other) =>
      other is ContentKey &&
      other.repoPath == repoPath &&
      other.text == text &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(repoPath, text, mode);

  @override
  String toString() => 'ContentKey($repoPath, $text, ${mode.name})';
}

/// Shas of every commit whose diff matched [ContentKey.text]. A commit carries
/// no diff, so this can only come from git's pickaxe.
///
/// Auto-disposed: every keystroke that survives the search bar's debounce is a
/// new key, and keeping each one alive would grow the cache for as long as the
/// repo stays open.
///
/// A failed read — a bad regular expression, or a search killed for running
/// too long — yields no shas: the graph then shows no matches, rather than
/// pretending the filter is off and highlighting the whole history.
final contentSearchProvider = FutureProvider.autoDispose
    .family<Set<String>, ContentKey>((ref, key) async {
      if (key.text.isEmpty) return const {};
      final git = ref.watch(gitServiceProvider);
      final flag = switch (key.mode) {
        // The search string is glued to the flag so one starting with `-` is
        // read as the thing to look for, not as another option.
        ContentSearchMode.occurrences => '-S${key.text}',
        ContentSearchMode.diffText => '-G${key.text}',
      };
      try {
        // Scanning every diff in the history is far slower than the reads this
        // app usually makes, so the default guard would kill legitimate
        // searches on a large repo.
        final r = await git.run(
          [
            'log',
            // The graph draws every branch, so the search has to walk every
            // branch too — walking HEAD alone would dim a matching commit
            // that is sitting right there on screen.
            '--all',
            '--pretty=format:%H',
            flag,
          ],
          repoPath: key.repoPath,
          timeout: const Duration(minutes: 2),
        );
        if (!r.ok) return const {};
        return r.stdout.split('\n').where((s) => s.isNotEmpty).toSet();
      } on Object {
        return const {};
      }
    });
