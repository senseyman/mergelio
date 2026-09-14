import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/conflict.dart';
import '../domain/git/models.dart';

/// A conflicted file inside a merge session: its parsed [parts] plus the
/// per-hunk [resolutions] chosen so far.
///
/// Some conflicts have no hunks to choose between — one side deleted the path,
/// or the content is binary. Those are [wholeFile] conflicts, settled with a
/// single [fileChoice] instead.
class ConflictFile {
  final String path;
  final List<ConflictPart> parts;
  final Map<int, Resolution> resolutions;
  final Map<int, List<String>> custom;

  /// Which sides of the merge still have content for this path.
  final ConflictKind kind;

  /// Content git could not merge as text.
  final bool binary;

  /// A gitlink: the conflict is over which commit the submodule points at.
  final bool submodule;

  /// The whole-file outcome chosen so far, when [wholeFile].
  final FileResolution? fileChoice;
  const ConflictFile({
    required this.path,
    required this.parts,
    this.resolutions = const {},
    this.custom = const {},
    this.kind = ConflictKind.bothModified,
    this.binary = false,
    this.submodule = false,
    this.fileChoice,
  });

  List<int> get hunkIndices => [
    for (var i = 0; i < parts.length; i++)
      if (parts[i] is ConflictHunk) i,
  ];

  /// True when there is nothing to merge line by line: binary content, a
  /// submodule gitlink, or a side that no longer has the path. A text file
  /// whose markers the user already edited away is not one of these — that
  /// content is the answer.
  bool get wholeFile => binary || submodule || !kind.hasOurs || !kind.hasTheirs;

  /// The outcomes this conflict can be resolved to. A side that deleted the
  /// path has no content to keep, so it is left out.
  List<FileResolution> get fileOptions => [
    if (kind.hasOurs) FileResolution.ours,
    if (kind.hasTheirs) FileResolution.theirs,
    FileResolution.delete,
  ];

  int get total => wholeFile ? 1 : hunkIndices.length;
  int get resolvedCount => wholeFile
      ? (fileChoice == null ? 0 : 1)
      : hunkIndices.where(resolutions.containsKey).length;
  bool get resolved => resolvedCount == total;

  /// Resolved file body, honouring the chosen resolutions. Meaningless for a
  /// [wholeFile] conflict, which git resolves by checking out a side instead.
  String content() => resolveConflicts(parts, resolutions, custom: custom);

  ConflictFile _copy({
    Map<int, Resolution>? resolutions,
    Map<int, List<String>>? custom,
    FileResolution? fileChoice,
  }) => ConflictFile(
    path: path,
    parts: parts,
    resolutions: resolutions ?? this.resolutions,
    custom: custom ?? this.custom,
    kind: kind,
    binary: binary,
    submodule: submodule,
    fileChoice: fileChoice ?? this.fileChoice,
  );

  ConflictFile withResolution(int hunk, Resolution r, {List<String>? lines}) =>
      _copy(
        resolutions: {...resolutions, hunk: r},
        custom: lines == null ? null : {...custom, hunk: lines},
      );

  ConflictFile withFileChoice(FileResolution r) => _copy(fileChoice: r);
}

/// What produced the conflicts being resolved. Resolving only ever stages the
/// result; how the operation is then closed differs by kind — [merge] waits for
/// an ordinary commit, [rebase], [cherryPick] and [revert] wait for a
/// `--continue`, and [stash] is already done once staged.
enum MergeKind { merge, rebase, cherryPick, revert, stash }

/// An operation git is in the middle of, still owed a commit or a `--continue`.
/// Read back from git's own state files, so it survives the app restarting
/// halfway through a merge.
class PendingOp {
  final MergeKind kind;

  /// The branch or short sha the operation is bringing in, when git records
  /// one. Empty for a rebase, which has no single source to name.
  final String branch;
  const PendingOp({required this.kind, this.branch = ''});

  /// Whether finishing this means `--continue` rather than a plain commit.
  bool get continues => kind != MergeKind.merge && kind != MergeKind.stash;
}

/// An in-progress conflict resolution for [branch] being merged in.
class MergeSession {
  final String branch;
  final List<ConflictFile> files;

  /// HEAD before the merge started, for undo of a finished merge.
  final String prevSha;

  /// How this session completes (see [MergeKind]).
  final MergeKind kind;

  /// A stash to drop once the session finishes (a conflicted `pop`), else null.
  final String? dropStashRef;
  const MergeSession({
    required this.branch,
    required this.files,
    this.prevSha = '',
    this.kind = MergeKind.merge,
    this.dropStashRef,
  });

  bool get allResolved => files.every((f) => f.resolved);
  int get totalConflicts => files.fold(0, (s, f) => s + f.total);
  int get resolvedConflicts => files.fold(0, (s, f) => s + f.resolvedCount);

  MergeSession withFiles(List<ConflictFile> newFiles) => MergeSession(
    branch: branch,
    prevSha: prevSha,
    kind: kind,
    dropStashRef: dropStashRef,
    files: newFiles,
  );

  MergeSession replaceFile(int index, ConflictFile file) => MergeSession(
    branch: branch,
    prevSha: prevSha,
    kind: kind,
    dropStashRef: dropStashRef,
    files: [
      for (var i = 0; i < files.length; i++) i == index ? file : files[i],
    ],
  );
}

/// The active merge session per repo, or null when not merging.
final mergeSessionProvider = StateProvider.family<MergeSession?, String>(
  (ref, path) => null,
);
