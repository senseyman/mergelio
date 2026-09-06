import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/blame.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/line_history.dart';
import '../domain/git/models.dart';

typedef FileKey = ({String repo, String path});

/// Commit history of a file, following renames.
final fileHistoryProvider = FutureProvider.family
    .autoDispose<List<Commit>, FileKey>(
      (ref, key) => GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).fileHistory(key.path),
    );

/// A range of lines in one file, resolved against the revision [rev] the line
/// numbers were read from.
typedef LineRangeKey = ({
  String repo,
  String path,
  int start,
  int end,
  String rev,
});

/// Commits that changed a line range, each with the range's diff.
final lineHistoryProvider = FutureProvider.family
    .autoDispose<List<LineHistoryEntry>, LineRangeKey>(
      (ref, key) => GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).lineHistory(key.path, key.start, key.end, rev: key.rev),
    );

/// Per-line blame of a file.
final blameProvider = FutureProvider.family
    .autoDispose<List<BlameLine>, FileKey>((ref, key) async {
      final raw = await GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).blame(key.path);
      return parseBlame(raw);
    });
