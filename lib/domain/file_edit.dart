import 'dart:io';

import 'package:path/path.dart' as p;

/// Files larger than this are not offered for in-place editing: the editor
/// holds the whole text in memory and re-lays it out on every keystroke.
const maxEditableBytes = 2 * 1024 * 1024;

/// How much of a file is sniffed for binary content, matching git's own
/// first-block heuristic. Callers read at most this much before deciding.
const sniffBytes = 8000;

/// Whether [bytes] look like a binary file. A NUL byte in the first block is
/// the same signal git uses to decide a file has no useful text diff.
bool looksBinary(List<int> bytes) {
  final n = bytes.length < sniffBytes ? bytes.length : sniffBytes;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// Why a file cannot be edited in the diff sheet, or null when it can be.
/// Editing writes the working tree, so anything that is not a present, textual
/// working-tree file is refused with a reason the sheet can show.
String? fileEditBlocker({
  required bool isWorkingTree,
  required bool exists,
  required bool binary,
  required int sizeBytes,
}) {
  if (!isWorkingTree) return 'Only uncommitted files can be edited';
  if (!exists) return 'This file is not in the working tree';
  if (binary) return 'Binary file — cannot be edited here';
  if (sizeBytes > maxEditableBytes) return 'File is too large to edit here';
  return null;
}

/// Whether [relPath] is a plain repo-relative path — the only shape git ever
/// reports for a working file. Rejects absolute paths, drive letters, UNC
/// shares and `..` segments so a hostile path cannot address files outside
/// the repository the user opened.
bool isRepoRelativePath(String relPath) {
  if (relPath.isEmpty) return false;
  if (relPath.startsWith('/') || relPath.startsWith(r'\')) return false;
  if (relPath.length >= 2 && relPath[1] == ':') return false;
  return !relPath.split(RegExp(r'[\\/]')).contains('..');
}

/// Whether [resolvedPath] is safely inside [repoRoot] after resolving symlinks.
/// Catches a symlink in the working tree that points outside the repo.
bool isInsideRepo(String repoRoot, String resolvedPath) {
  final repoDir = Directory(repoRoot);
  final file = File(resolvedPath);
  // Resolve to real paths, following symlinks. If either side fails (deleted,
  // permission denied) refuse the path — it is not worth the risk.
  String? realRepo, realFile;
  try {
    realRepo = repoDir.resolveSymbolicLinksSync();
  } on FileSystemException {
    return false;
  }
  try {
    realFile = file.resolveSymbolicLinksSync();
  } on FileSystemException {
    return false;
  }
  return isWithinOrEqual(realRepo, realFile);
}

/// Whether [path] is [root] itself or sits beneath it. Purely lexical, so both
/// sides must already be resolved absolute paths. [context] defaults to the
/// host platform; tests pass `p.windows` to exercise drive letters and
/// backslash separators from any host.
bool isWithinOrEqual(String root, String path, {p.Context? context}) {
  final ctx = context ?? p.context;
  return ctx.equals(root, path) || ctx.isWithin(root, path);
}

/// Whether [file] was written after [loadedAt] — something outside the editor
/// (another editor, a git command) changed it while it sat open. A file that
/// has since been deleted reports false; saving will simply recreate it.
Future<bool> fileChangedSince(File file, DateTime? loadedAt) async {
  if (loadedAt == null) return false;
  try {
    if (!await file.exists()) return false;
    return (await file.lastModified()).isAfter(loadedAt);
  } on FileSystemException {
    // The file went away between the two calls. Nothing to overwrite, so
    // there is nothing to warn about — the save will recreate it.
    return false;
  }
}
