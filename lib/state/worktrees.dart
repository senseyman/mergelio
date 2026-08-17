import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/worktree.dart';

/// Every worktree of the repository at the given path.
///
/// Deliberately a sibling of `repoDataProvider` rather than a field on it: the
/// list changes rarely and is shared by every worktree of one repository, so
/// folding it into the per-repo bundle would refetch it on every status tick.
final worktreesProvider = FutureProvider.family<List<Worktree>, String>((
  ref,
  path,
) async {
  final reader = GitReader(ref.watch(gitServiceProvider), path);
  return reader.worktrees();
});

/// Branch name -> the worktree holding it. Used to badge branches that are
/// checked out elsewhere before the user tries to switch to them. Empty while
/// the list is still loading, so callers need no async handling.
final worktreeByBranchProvider = Provider.family<Map<String, Worktree>, String>(
  (ref, path) {
    final list =
        ref.watch(worktreesProvider(path)).valueOrNull ?? const <Worktree>[];
    return {
      for (final w in list)
        if (w.branch != null) w.branch!: w,
    };
  },
);

/// True when [path] is itself a linked worktree — its `.git` is a file
/// pointing at a `worktrees` administrative directory in the main repository.
///
/// Answered from the path alone rather than from a parent repository's list,
/// so it works for a tab whose parent repository is not open. The `.git` file
/// alone is not the answer: a submodule checkout keeps one too, pointing at
/// `.git/modules/<name>` instead, and would otherwise wear the worktree glyph.
final isLinkedWorktreeProvider = FutureProvider.family<bool, String>((
  ref,
  path,
) async {
  return await ref.watch(worktreeParentProvider(path).future) != null;
});

/// The main repository directory behind a linked worktree, or null when [path]
/// is not one. Drives the tab tooltip.
final worktreeParentProvider = FutureProvider.family<String?, String>((
  ref,
  path,
) async {
  final marker = File('$path/.git');
  if (!await marker.exists()) return null;
  final gitDir = parseGitdirFile(await marker.readAsString());
  if (gitDir == null) return null;
  // <main>/.git/worktrees/<name> -> <main>. The `.git` segment alone is not
  // enough to identify the boundary: a linked worktree may itself be called
  // `.git`, and cutting at that would silently name the wrong directory as the
  // parent. Only a `.git/worktrees/…` pair marks a real administrative dir.
  final parts = gitDir.replaceAll('\\', '/').split('/');
  final i = parts.lastIndexOf('.git');
  if (i <= 0) return null;
  if (i + 1 >= parts.length || parts[i + 1] != 'worktrees') return null;
  return parts.sublist(0, i).join('/');
});

/// Reads the `gitdir: <path>` pointer a linked worktree keeps in place of a
/// `.git` directory. Returns null for anything else.
String? parseGitdirFile(String content) {
  for (final line in content.split('\n')) {
    final t = line.trim();
    if (t.startsWith('gitdir:')) {
      final v = t.substring('gitdir:'.length).trim();
      return v.isEmpty ? null : v;
    }
  }
  return null;
}

/// Where this checkout's git state actually lives: `<repo>/.git` for a normal
/// clone, or the `<main>/.git/worktrees/<name>` directory a linked worktree's
/// `.git` file points at. Null when [repoPath] holds no git state.
///
/// The watcher needs this: a linked worktree's refs change outside its own
/// directory tree, so watching only the working tree misses branch switches.
String? resolveGitDir(String repoPath) {
  final asDir = Directory('$repoPath/.git');
  if (asDir.existsSync()) return asDir.path;
  final asFile = File('$repoPath/.git');
  if (!asFile.existsSync()) return null;
  final target = parseGitdirFile(asFile.readAsStringSync());
  if (target == null) return null;
  return Directory(target).existsSync() ? target : null;
}
