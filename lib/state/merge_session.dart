import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/conflict.dart';

/// A conflicted file inside a merge session: its parsed [parts] plus the
/// per-hunk [resolutions] chosen so far.
class ConflictFile {
  final String path;
  final List<ConflictPart> parts;
  final Map<int, Resolution> resolutions;
  final Map<int, List<String>> custom;
  const ConflictFile({
    required this.path,
    required this.parts,
    this.resolutions = const {},
    this.custom = const {},
  });

  List<int> get hunkIndices => [
    for (var i = 0; i < parts.length; i++)
      if (parts[i] is ConflictHunk) i,
  ];

  int get total => hunkIndices.length;
  int get resolvedCount => hunkIndices.where(resolutions.containsKey).length;
  bool get resolved => resolvedCount == total;

  /// Resolved file body, honouring the chosen resolutions.
  String content() => resolveConflicts(parts, resolutions, custom: custom);

  ConflictFile withResolution(int hunk, Resolution r, {List<String>? lines}) =>
      ConflictFile(
        path: path,
        parts: parts,
        resolutions: {...resolutions, hunk: r},
        custom: lines == null ? custom : {...custom, hunk: lines},
      );
}

/// An in-progress conflict resolution for [branch] being merged in.
class MergeSession {
  final String branch;
  final List<ConflictFile> files;

  /// HEAD before the merge started, for undo of a finished merge.
  final String prevSha;

  /// True when these conflicts arose during a rebase (finish runs
  /// `rebase --continue` instead of a merge commit).
  final bool isRebase;
  const MergeSession({
    required this.branch,
    required this.files,
    this.prevSha = '',
    this.isRebase = false,
  });

  bool get allResolved => files.every((f) => f.resolved);
  int get totalConflicts => files.fold(0, (s, f) => s + f.total);
  int get resolvedConflicts => files.fold(0, (s, f) => s + f.resolvedCount);

  MergeSession withFiles(List<ConflictFile> newFiles) => MergeSession(
    branch: branch,
    prevSha: prevSha,
    isRebase: isRebase,
    files: newFiles,
  );

  MergeSession replaceFile(int index, ConflictFile file) => MergeSession(
    branch: branch,
    prevSha: prevSha,
    isRebase: isRebase,
    files: [
      for (var i = 0; i < files.length; i++) i == index ? file : files[i],
    ],
  );
}

/// The active merge session per repo, or null when not merging.
final mergeSessionProvider = StateProvider.family<MergeSession?, String>(
  (ref, path) => null,
);
