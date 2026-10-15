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

/// How blame reads a file. One value for the session: the choices are about
/// how the user wants to read history, not about any one repository.
class BlameOptions {
  final bool ignoreWhitespace;
  final BlameMoves moves;

  /// See past the commits a found ignore-revs file lists. Only means anything
  /// where [blameIgnoreRevsProvider] finds one.
  final bool skipIgnoredRevs;

  const BlameOptions({
    this.ignoreWhitespace = false,
    this.moves = BlameMoves.off,
    this.skipIgnoredRevs = true,
  });

  /// Plain git blame, with a project's own revs file honoured as it asks.
  bool get isDefault => this == const BlameOptions();

  BlameOptions copyWith({
    bool? ignoreWhitespace,
    BlameMoves? moves,
    bool? skipIgnoredRevs,
  }) => BlameOptions(
    ignoreWhitespace: ignoreWhitespace ?? this.ignoreWhitespace,
    moves: moves ?? this.moves,
    skipIgnoredRevs: skipIgnoredRevs ?? this.skipIgnoredRevs,
  );

  @override
  bool operator ==(Object other) =>
      other is BlameOptions &&
      other.ignoreWhitespace == ignoreWhitespace &&
      other.moves == moves &&
      other.skipIgnoredRevs == skipIgnoredRevs;

  @override
  int get hashCode => Object.hash(ignoreWhitespace, moves, skipIgnoredRevs);
}

/// Blame's options. Whitespace starts out as the diff sheet has it, so a user
/// who ignores whitespace there gets the same here; it is read rather than
/// watched, so from then on the blame toggle is its own.
final blameOptionsProvider = StateProvider<BlameOptions>(
  (ref) => BlameOptions(
    ignoreWhitespace: ref.read(diffViewOptionsProvider).ignoresWhitespace,
  ),
);

/// The ignore-revs file found for [repo], or null when it has none. One that
/// git would refuse is reported here and left out of every blame.
final blameIgnoreRevsProvider = FutureProvider.family
    .autoDispose<BlameRevsFile?, String>(
      (ref, repo) =>
          GitReader(ref.watch(gitServiceProvider), repo).blameIgnoreRevsFile(),
    );

/// Per-line blame of a file, read with [blameOptionsProvider].
final blameProvider = FutureProvider.family
    .autoDispose<List<BlameLine>, FileKey>((ref, key) async {
      final options = ref.watch(blameOptionsProvider);
      final found = options.skipIgnoredRevs
          ? await ref.watch(blameIgnoreRevsProvider(key.repo).future)
          : null;
      final revsFile = found?.invalid == null ? found?.path : null;
      final raw = await GitReader(ref.watch(gitServiceProvider), key.repo)
          .blame(
            key.path,
            rev: key.rev,
            ignoreWhitespace: options.ignoreWhitespace,
            moves: options.moves,
            ignoreRevsFile: revsFile,
          );
      return parseBlame(raw);
    });
