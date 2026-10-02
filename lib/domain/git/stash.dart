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

  /// Repo-relative paths to stash; empty takes every candidate.
  final List<String> paths;

  const StashPushOptions({
    this.message,
    this.stagedOnly = false,
    this.keepIndex = false,
    this.includeUntracked = false,
    this.paths = const [],
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

/// Arguments for `git stash push` under [o]. Paths are passed as literal
/// pathspecs so a file named `*.md` stashes that file, not every markdown one.
List<String> stashPushArgs(StashPushOptions o) => [
  'stash',
  'push',
  if (o.stagedOnly) '--staged',
  if (o.keepIndex && !o.stagedOnly) '--keep-index',
  if (o.includeUntracked && !o.stagedOnly) '--include-untracked',
  if (o.message != null) ...['-m', o.message!],
  if (o.paths.isNotEmpty) ...['--', for (final p in o.paths) ':(literal)$p'],
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

/// The pathspec that stashes only [selected] out of [candidates]: empty when
/// the selection covers every candidate, so a plain push does the same job.
/// A rename names both of its paths, or git would stash half of the move.
///
/// An empty [selected] also yields an empty pathspec; callers must refuse to
/// push with nothing selected rather than stash everything.
List<String> stashPathspec(List<WorkingFile> candidates, Set<String> selected) {
  final chosen = [
    for (final f in candidates)
      if (selected.contains(f.path)) f,
  ];
  if (chosen.length == candidates.length) return const [];
  return [
    for (final f in chosen) ...[
      if (f.origPath != null && f.origPath != f.path) f.origPath!,
      f.path,
    ],
  ];
}

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
