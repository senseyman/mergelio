import 'dart:convert';

import '../path_key.dart';

/// The role a worktree plays in its repository. The main worktree is the
/// original checkout; linked worktrees are the ones `git worktree add` makes.
enum WorktreeKind { main, linked, bare }

/// One entry of `git worktree list`. [branch] is the short name; a detached or
/// bare entry has none. [lockReason] may be null even when [locked] — git
/// allows locking without a reason.
class Worktree {
  final String path;
  final String? head;
  final String? branch;
  final bool detached;
  final bool locked;
  final String? lockReason;
  final bool prunable;
  final String? prunableReason;
  final WorktreeKind kind;

  const Worktree({
    required this.path,
    this.head,
    this.branch,
    this.detached = false,
    this.locked = false,
    this.lockReason,
    this.prunable = false,
    this.prunableReason,
    this.kind = WorktreeKind.linked,
  });

  String get shortHead =>
      head == null ? '' : (head!.length > 7 ? head!.substring(0, 7) : head!);

  /// The last path segment, used as the row label when there is no branch.
  String get name =>
      path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ??
      path;
}

const _headsPrefix = 'refs/heads/';

/// Parses `git worktree list --porcelain`: stanzas separated by a blank line,
/// each starting with `worktree <path>`. Unknown attribute lines are ignored,
/// so a newer git that adds fields does not break the parse.
List<Worktree> parseWorktreeList(String porcelain) {
  final out = <Worktree>[];
  String? path;
  String? head;
  String? branch;
  String? lockReason;
  String? prunableReason;
  var detached = false;
  var bare = false;
  var locked = false;
  var prunable = false;

  void flush() {
    if (path != null) {
      out.add(
        Worktree(
          path: path!,
          head: head,
          branch: branch,
          detached: detached,
          locked: locked,
          lockReason: lockReason,
          prunable: prunable,
          prunableReason: prunableReason,
          kind: bare
              ? WorktreeKind.bare
              : (out.isEmpty ? WorktreeKind.main : WorktreeKind.linked),
        ),
      );
    }
    path = null;
    head = null;
    branch = null;
    lockReason = null;
    prunableReason = null;
    detached = false;
    bare = false;
    locked = false;
    prunable = false;
  }

  for (final raw in const LineSplitter().convert(porcelain)) {
    // trimRight, not trim: a path may legitimately begin with a space, so only
    // the trailing \r of CRLF output is stripped.
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('worktree ')) {
      flush();
      path = line.substring('worktree '.length);
    } else if (line.startsWith('HEAD ')) {
      head = line.substring('HEAD '.length);
    } else if (line.startsWith('branch ')) {
      final ref = line.substring('branch '.length);
      branch = ref.startsWith(_headsPrefix)
          ? ref.substring(_headsPrefix.length)
          : null;
    } else if (line == 'detached') {
      detached = true;
    } else if (line == 'bare') {
      bare = true;
    } else if (line == 'locked') {
      locked = true;
    } else if (line.startsWith('locked ')) {
      locked = true;
      lockReason = line.substring('locked '.length);
    } else if (line == 'prunable') {
      prunable = true;
    } else if (line.startsWith('prunable ')) {
      prunable = true;
      prunableReason = line.substring('prunable '.length);
    }
  }
  flush();
  return out;
}

/// The worktree currently holding [branch] checked out, or null when the
/// branch is free. Git refuses to check out a branch a second time, so this is
/// the pre-flight check that runs before a checkout.
Worktree? worktreeHolding(List<Worktree> all, String branch) {
  for (final w in all) {
    if (w.branch == branch) return w;
  }
  return null;
}

/// Suggests a sibling directory named after the repository and branch, e.g.
/// `/home/u/repo` + `feat/login` -> `/home/u/repo-feat-login`. Only a
/// suggestion: the user is free to replace it.
String suggestWorktreePath(String repoPath, String branch) {
  var trimmed = repoPath;
  while (trimmed.length > 1 &&
      (trimmed.endsWith('/') || trimmed.endsWith('\\'))) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final cut = trimmed.lastIndexOf(RegExp(r'[/\\]'));
  final sep = cut < 0 ? '/' : trimmed[cut];
  final dir = cut < 0 ? '' : trimmed.substring(0, cut);
  final leaf = cut < 0 ? trimmed : trimmed.substring(cut + 1);
  final slug = branch
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final name = slug.isEmpty ? '$leaf-worktree' : '$leaf-$slug';
  return dir.isEmpty ? name : '$dir$sep$name';
}

/// Checks a proposed worktree location. Returns a message to show the user, or
/// null when the destination is acceptable.
///
/// Comparisons go through [repoPathKey], which resolves symlinks — a
/// destination that does not exist yet is still keyed against the deepest
/// ancestor that does, so a location genuinely inside the repository is caught
/// even when the repository sits under a symlinked ancestor. Whether the
/// directory already exists and is non-empty is the caller's question; this
/// function does not ask it.
String? validateWorktreeDestination({
  required String destination,
  required String repoPath,
  required List<Worktree> existing,
}) {
  final dest = destination.trim();
  if (dest.isEmpty) return 'Choose a location';
  final destKey = repoPathKey(dest);
  final repoKey = repoPathKey(repoPath);
  if (destKey == repoKey) return 'That is the repository itself';
  if (destKey.startsWith('$repoKey/')) {
    return 'Choose a location outside the repository';
  }
  for (final w in existing) {
    if (repoPathKey(w.path) == destKey) {
      return 'A worktree already lives there';
    }
  }
  return null;
}

/// Cheap pre-flight on a branch name. Git's own `check-ref-format` is the real
/// authority and its error still surfaces; this only spares the user a round
/// trip on the obvious mistakes.
String? validateNewBranchName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Enter a branch name';
  if (n != name) return 'Branch names cannot start or end with a space';
  if (n.startsWith('-')) return 'Branch names cannot start with "-"';
  if (n.endsWith('/') || n.endsWith('.')) return 'Invalid branch name';
  if (n.contains('..') || n.contains('//')) return 'Invalid branch name';
  if (RegExp(r'[\s~^:?*\[\\]').hasMatch(n)) {
    return 'Branch names cannot contain spaces or ~ ^ : ? * [ \\';
  }
  // `@{` is how a reflog position is spelled, so a name containing it could
  // never be told apart from one; `HEAD` names the current checkout.
  if (n.contains('@{')) return 'Invalid branch name';
  if (n == 'HEAD') return 'HEAD is not a branch name';
  // Path components may not start with a dot or end in .lock — git reserves
  // both for its own files under refs/.
  for (final part in n.split('/')) {
    if (part.startsWith('.') || part.endsWith('.lock')) {
      return 'Invalid branch name';
    }
  }
  if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(n)) return 'Invalid branch name';
  return null;
}
