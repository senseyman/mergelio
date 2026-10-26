import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_reader.dart';
import 'settings.dart';

/// Context widths offered in the diff sheet, besides the whole-file view.
const kDiffContextChoices = [3, 5, 10];

/// How the diff sheet reads every diff: whitespace handling and how many
/// unchanged lines surround each change. The whole-file view stays on
/// the diff target because it belongs to one open file, not to every diff.
class DiffViewOptions {
  final DiffWhitespace whitespace;
  final int contextLines;
  const DiffViewOptions({
    this.whitespace = DiffWhitespace.show,
    this.contextLines = 3,
  });

  /// Reads the stored choice, falling back to the default for anything a
  /// newer or older build might have written.
  factory DiffViewOptions.fromSettings(AppSettings s) => DiffViewOptions(
    whitespace:
        DiffWhitespace.values.asNameMap()[s.diffWhitespace] ??
        DiffWhitespace.show,
    contextLines: kDiffContextChoices.contains(s.diffContextLines)
        ? s.diffContextLines
        : 3,
  );

  bool get isDefault => this == const DiffViewOptions();

  bool get ignoresWhitespace => whitespace != DiffWhitespace.show;

  /// The `-U` width to ask git for. Git's own default needs no flag, which
  /// also keeps a user's `diff.context` setting in charge of it.
  int? contextArg({required bool wholeFile}) => wholeFile
      ? kWholeFileContext
      : contextLines == 3
      ? null
      : contextLines;

  DiffViewOptions copyWith({DiffWhitespace? whitespace, int? contextLines}) =>
      DiffViewOptions(
        whitespace: whitespace ?? this.whitespace,
        contextLines: contextLines ?? this.contextLines,
      );

  @override
  bool operator ==(Object other) =>
      other is DiffViewOptions &&
      other.whitespace == whitespace &&
      other.contextLines == contextLines;

  @override
  int get hashCode => Object.hash(whitespace, contextLines);
}

/// The diff sheet's current options. Seeded from settings at startup; kept
/// apart from [settingsProvider] so diff readers need nothing overridden to
/// run with the defaults.
final diffViewOptionsProvider = StateProvider<DiffViewOptions>(
  (_) => const DiffViewOptions(),
);
