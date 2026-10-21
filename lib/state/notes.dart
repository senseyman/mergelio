import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'repo_data.dart';

/// Every commit in the repository with a note, mapped to the note's blob.
/// One `git notes list` per refresh: every note action ends in one, and
/// watching the repository data is what re-reads this. Kept while the
/// repository is open, so the graph menu knows at once whether a commit has
/// a note to edit.
final noteIndexProvider = FutureProvider.family<Map<String, String>, String>((
  ref,
  repo,
) {
  ref.watch(repoDataProvider(repo));
  return GitReader(ref.watch(gitServiceProvider), repo).noteIndex();
});

/// The note on one commit. Asked for only when [noteIndexProvider] lists the
/// commit, so a commit without a note costs no git process. [blob] is the
/// note's blob from that index: an edited note changes it and is read again,
/// an untouched one is not.
final commitNoteProvider = FutureProvider.family
    .autoDispose<String, ({String repo, String sha, String blob})>((
      ref,
      key,
    ) async {
      try {
        return await GitReader(
              ref.watch(gitServiceProvider),
              key.repo,
            ).note(key.sha) ??
            '';
      } catch (e) {
        appLog.warn(
          'reading the note on ${key.sha} failed: $e',
          scope: 'notes',
        );
        rethrow;
      }
    });
