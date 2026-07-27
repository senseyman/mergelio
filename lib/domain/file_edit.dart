import 'dart:io';

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
