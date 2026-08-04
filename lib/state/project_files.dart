import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/quoted_path.dart';

/// How many entries one directory contributes to the navigator. A directory
/// holding more than this is listed up to the cap and the remainder is
/// reported as a count, so a pathological folder cannot stall the UI.
const maxDirEntries = 5000;

/// Identifies one directory inside one repository. Value equality is what lets
/// the listing family cache per directory rather than per call.
class DirKey {
  final String repoPath;

  /// Repo-relative, `/`-separated. Empty means the repository root.
  final String relDir;
  const DirKey(this.repoPath, this.relDir);

  @override
  bool operator ==(Object other) =>
      other is DirKey && other.repoPath == repoPath && other.relDir == relDir;

  @override
  int get hashCode => Object.hash(repoPath, relDir);

  @override
  String toString() => 'DirKey($repoPath, $relDir)';
}

/// One child of a listed directory. Symlinks are reported as links and never
/// followed, so a link loop cannot be walked into.
class DirEntry {
  final String name;
  final bool isDir;
  final bool isLink;
  const DirEntry({
    required this.name,
    required this.isDir,
    this.isLink = false,
  });
}

/// The result of listing one directory: its children, how many were dropped by
/// the cap, and why it could not be read at all.
class DirListing {
  final List<DirEntry> entries;
  final int truncated;
  final String? error;
  const DirListing({this.entries = const [], this.truncated = 0, this.error});
}

/// Lists one directory of the working tree — never recursively. The navigator
/// reads a directory only when it is expanded, so the cost of a large tree is
/// paid per folder the user actually opens.
final dirListingProvider = FutureProvider.family<DirListing, DirKey>((
  ref,
  key,
) async {
  final dir = Directory(
    key.relDir.isEmpty ? key.repoPath : '${key.repoPath}/${key.relDir}',
  );
  final entries = <DirEntry>[];
  var seen = 0;
  try {
    await for (final e in dir.list(recursive: false, followLinks: false)) {
      final name = _basename(e.path);
      // The repository's own .git is machinery, not project content: editing
      // loose objects or refs by hand corrupts the repo. A nested .git (a
      // submodule or vendored checkout) is left alone.
      if (key.relDir.isEmpty && name == '.git') continue;
      seen++;
      if (entries.length < maxDirEntries) {
        entries.add(
          DirEntry(name: name, isDir: e is Directory, isLink: e is Link),
        );
      }
    }
  } on FileSystemException catch (e) {
    return DirListing(error: e.osError?.message ?? e.message);
  }
  // Directories first, then files; within each group, case-insensitive by name
  // so a listing reads the way the file manager shows it.
  entries.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return DirListing(entries: entries, truncated: seen - entries.length);
});

/// How many paths one `git check-ignore` invocation is asked about. Keeps the
/// command line well under every platform's argument limit even when a
/// directory is listed up to [maxDirEntries].
const _checkIgnoreChunk = 1000;

/// Every path git tracks in the repository, or null when the read failed.
///
/// Null is not the same as empty: an empty set means git tracks nothing, while
/// null means nothing is known, and the navigator then shows no status at all
/// rather than declaring the whole project untracked.
final trackedPathsProvider = FutureProvider.family<Set<String>?, String>((
  ref,
  repoPath,
) async {
  final git = ref.watch(gitServiceProvider);
  final r = await git.run(['ls-files', '-z'], repoPath: repoPath);
  if (!r.ok) return null;
  return r.stdout.split('\u0000').where((s) => s.isNotEmpty).toSet();
});

/// Which children of one directory an ignore rule covers, as repo-relative
/// paths. Asked per directory as it is expanded, so an unopened `node_modules`
/// costs nothing.
///
/// A failed check leaves the directory unignored: ignore state decorates the
/// tree, and losing it must never stop a file being browsed or opened.
final ignoredInDirProvider = FutureProvider.family<Set<String>, DirKey>((
  ref,
  key,
) async {
  final listing = await ref.watch(dirListingProvider(key).future);
  if (listing.entries.isEmpty) return const {};
  final paths = [
    for (final e in listing.entries)
      key.relDir.isEmpty ? e.name : '${key.relDir}/${e.name}',
  ];
  final git = ref.watch(gitServiceProvider);
  final ignored = <String>{};
  for (var i = 0; i < paths.length; i += _checkIgnoreChunk) {
    final chunk = paths.sublist(
      i,
      (i + _checkIgnoreChunk).clamp(0, paths.length),
    );
    final r = await git.run([
      // Paths come back one per line; without this a non-ASCII name would be
      // printed as octal escapes even when nothing about it needs quoting.
      '-c',
      'core.quotepath=false',
      'check-ignore',
      '--no-index',
      '--',
      ...chunk,
    ], repoPath: key.repoPath);
    // Exit 1 is git's "none of these are ignored"; anything higher is a real
    // failure. Both leave this chunk unignored.
    if (!r.ok) continue;
    ignored.addAll(
      r.stdout.split('\n').where((s) => s.isNotEmpty).map(unquoteGitPath),
    );
  }
  return ignored;
});

String _basename(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? path : path.substring(i + 1);
}
