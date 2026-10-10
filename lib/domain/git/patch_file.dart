import 'git_service.dart';

/// How a patch file is applied. None of them commits: a mailbox's messages
/// and authors are left behind, and the user commits the result.
enum PatchMode {
  /// `git apply`: changes the working tree only.
  worktree,

  /// `git apply --index`: changes the working tree and stages the result.
  stage,

  /// `git apply --3way`: falls back on the blobs the patch names and leaves
  /// conflicts, staged as unmerged, where a hunk does not fit.
  threeWay,
}

/// What a `git apply --check --3way` dry run predicted.
enum ThreeWayCheck { unavailable, clean, conflicts }

/// One file a patch touches. [added] and [deleted] are null for a binary
/// change, which git counts as `-`.
class PatchFileStat {
  final String path;
  final int? added;
  final int? deleted;
  const PatchFileStat(this.path, this.added, this.deleted);
}

/// Everything shown before a patch file is applied.
class PatchPreview {
  final List<PatchFileStat> files;

  /// One entry per message when the file is a mailbox, empty for a plain
  /// diff.
  final List<String> subjects;
  final bool worktreeOk;
  final bool stageOk;
  final ThreeWayCheck threeWay;

  /// Git's complaint from the direct dry run, for when nothing applies.
  final String error;

  const PatchPreview({
    required this.files,
    required this.subjects,
    required this.worktreeOk,
    required this.stageOk,
    required this.threeWay,
    required this.error,
  });

  /// The modes that will go through, the safest first. A 3-way merge is only
  /// offered when a direct apply cannot work, since it may leave conflicts.
  List<PatchMode> get modes => [
    if (worktreeOk) PatchMode.worktree,
    if (stageOk) PatchMode.stage,
    if (!worktreeOk && threeWay != ThreeWayCheck.unavailable)
      PatchMode.threeWay,
  ];
}

final _mboxSeparator = RegExp(r'^From \S+ ');
final _patchTag = RegExp(r'^\[PATCH[^\]]*\]\s*');

/// The subject of every message in a `git format-patch` mailbox, with the
/// `[PATCH n/m]` tag taken off and folded header lines joined. Only header
/// blocks are read, so a diff line that happens to say `Subject:` is not
/// mistaken for one.
List<String> mailboxSubjects(String text) {
  final subjects = <String>[];
  var inHeaders = false;
  String? subject;
  void flush() {
    if (subject != null) subjects.add(subject!.replaceFirst(_patchTag, ''));
    subject = null;
  }

  for (var line in text.split('\n')) {
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (_mboxSeparator.hasMatch(line)) {
      flush();
      inHeaders = true;
      continue;
    }
    if (!inHeaders) continue;
    if (line.isEmpty) {
      flush();
      inHeaders = false;
    } else if (subject != null && (line[0] == ' ' || line[0] == '\t')) {
      subject = '${subject!} ${line.trim()}';
    } else {
      flush();
      if (line.startsWith('Subject:')) {
        subject = line.substring('Subject:'.length).trim();
      }
    }
  }
  flush();
  return subjects;
}

/// Reads `git apply --numstat -z`. A series that touches a path more than
/// once lists it once, with the counts summed.
List<PatchFileStat> parsePatchNumstat(String out) {
  final byPath = <String, PatchFileStat>{};
  for (final record in out.split('\x00')) {
    final parts = record.split('\t');
    if (parts.length < 3) continue;
    final path = parts.sublist(2).join('\t');
    final added = int.tryParse(parts[0]);
    final deleted = int.tryParse(parts[1]);
    final prev = byPath[path];
    byPath[path] = prev == null
        ? PatchFileStat(path, added, deleted)
        : PatchFileStat(
            path,
            prev.added == null || added == null ? null : prev.added! + added,
            prev.deleted == null || deleted == null
                ? null
                : prev.deleted! + deleted,
          );
  }
  return byPath.values.toList();
}

/// Git passes a 3-way dry run that would conflict, saying so only on stderr.
ThreeWayCheck threeWayCheckOf(GitResult r) {
  if (!r.ok) return ThreeWayCheck.unavailable;
  return r.stderr.contains('with conflicts')
      ? ThreeWayCheck.conflicts
      : ThreeWayCheck.clean;
}
