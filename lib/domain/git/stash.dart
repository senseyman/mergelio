import 'diff.dart';
import 'models.dart';

/// What a `git stash push` should take, and what it should leave behind.
class StashPushOptions {
  final String? message;

  /// Only what is in the index (`--staged`). Git rejects it beside
  /// [includeUntracked], and [keepIndex] means nothing next to it, so both are
  /// dropped when this is set.
  final bool stagedOnly;

  /// Stash everything but leave the staged changes in place (`--keep-index`).
  final bool keepIndex;
  final bool includeUntracked;

  /// Repo-relative paths to leave out; empty takes every candidate.
  final List<String> exclude;

  const StashPushOptions({
    this.message,
    this.stagedOnly = false,
    this.keepIndex = false,
    this.includeUntracked = false,
    this.exclude = const [],
  });
}

/// What a stash holds, read without applying it.
class StashContents {
  /// The commit the stash was made on: its tracked changes are diffed against
  /// this.
  final String baseSha;

  /// The root commit holding the untracked files of a `-u` stash, else null.
  final String? untrackedSha;

  /// Tracked changes, as the stash would apply them.
  final List<CommitFileChange> files;

  /// Untracked files the stash carries, created anew when applied.
  final List<String> untracked;

  const StashContents({
    required this.baseSha,
    this.untrackedSha,
    this.files = const [],
    this.untracked = const [],
  });
}

/// Arguments for `git stash push` under [o].
///
/// A partial stash names what to leave out rather than what to take: git
/// refuses a pathspec naming a file the index no longer has, which is the old
/// side of every staged rename, while an exclusion need not match anything.
/// Paths are literal so `*.md` means that one file, not every markdown file.
List<String> stashPushArgs(StashPushOptions o) => [
  'stash',
  'push',
  if (o.stagedOnly) '--staged',
  if (o.keepIndex && !o.stagedOnly) '--keep-index',
  if (o.includeUntracked && !o.stagedOnly) '--include-untracked',
  if (o.message != null) ...['-m', o.message!],
  if (o.exclude.isNotEmpty) ...[
    '--',
    ':/',
    for (final p in o.exclude) ':(exclude,literal)$p',
  ],
];

/// The files of [working] a push under [o] could take: what is staged when
/// only the index is stashed, otherwise every tracked change, plus untracked
/// files when they are included. Conflicted files are never offered — git
/// refuses to stash an unmerged index.
List<WorkingFile> stashCandidates(
  List<WorkingFile> working,
  StashPushOptions o,
) => [
  for (final f in working)
    if (!f.isConflicted &&
        (o.stagedOnly ? f.isStaged : !f.isUntracked || o.includeUntracked))
      f,
];

/// The paths to exclude so a push takes only [selected] out of [candidates]:
/// empty when everything is selected. An unselected rename excludes both of
/// its paths, or git would stash half of the move.
///
/// An empty [selected] excludes every candidate, which leaves git nothing to
/// stash; callers should refuse to push instead.
List<String> stashExclusions(
  List<WorkingFile> candidates,
  Set<String> selected,
) => [
  for (final f in candidates)
    if (!selected.contains(f.path)) ...[
      if (f.origPath != null && f.origPath != f.path) f.origPath!,
      f.path,
    ],
];

final _stashRef = RegExp(r'^stash@\{(\d+)\}$');

/// The position in the stash list named by [ref] (`stash@{n}`), or null when
/// [ref] is not such a selector.
int? stashIndexOf(String ref) {
  final m = _stashRef.firstMatch(ref);
  return m == null ? null : int.parse(m.group(1)!);
}

String stashRefAt(int index) => 'stash@{$index}';

/// Whether [file], from a stash's diff, can be applied a hunk at a time. A
/// hunk patch only edits lines in place, so it needs a text file that exists
/// on both sides under one name; anything else is applied as a whole file.
bool canApplyStashHunks(FileDiff file) =>
    file.status == GitChange.modified &&
    !file.binary &&
    file.lfs == null &&
    file.hunks.isNotEmpty;
