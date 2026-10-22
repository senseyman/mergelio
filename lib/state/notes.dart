import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'repo_data.dart';

/// Every commit in the repository with a note, mapped to the note's blob.
/// Follows the notes refs the repository data last read, so `git notes list`
/// runs only when a note changed, not on every refresh, and never in a
/// repository without notes. Kept while the repository is open, so the graph
/// menu can tell from what is already here whether a commit has a note.
final noteIndexProvider = FutureProvider.family<Map<String, String>, String>((
  ref,
  repo,
) async {
  final sig = ref.watch(
    repoDataProvider(repo).select((d) => d.valueOrNull?.notesSignature),
  );
  // Not loaded yet, or no notes refs at all: nothing to list.
  if (sig == null || sig.isEmpty) return const {};
  try {
    return await GitReader(ref.watch(gitServiceProvider), repo).noteIndex();
  } catch (e) {
    appLog.warn('listing notes failed: $e', scope: 'notes');
    rethrow;
  }
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
