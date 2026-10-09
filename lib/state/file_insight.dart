import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/blame.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/line_history.dart';
import '../domain/git/models.dart';
import 'diff_view_options.dart';

/// A file, read as of [rev] when given, else as checked out.
typedef FileKey = ({String repo, String path, String? rev});

/// Commit history of a file, following renames, walked back from [FileKey.rev]
/// or HEAD.
final fileHistoryProvider = FutureProvider.family
    .autoDispose<List<Commit>, FileKey>(
      (ref, key) => GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).fileHistory(key.path, rev: key.rev),
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

/// Per-line blame of a file. Ignores whitespace whenever the diff sheet does,
/// so a reformat does not take credit for lines it only re-indented.
final blameProvider = FutureProvider.family
    .autoDispose<List<BlameLine>, FileKey>((ref, key) async {
      final ignoreWhitespace = ref.watch(
        diffViewOptionsProvider.select((o) => o.ignoresWhitespace),
      );
      final raw = await GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).blame(key.path, rev: key.rev, ignoreWhitespace: ignoreWhitespace);
      return parseBlame(raw);
    });
