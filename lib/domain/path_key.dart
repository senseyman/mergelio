import 'dart:io';

/// Key for comparing repository paths. Separators are normalised to `/`,
/// trailing slashes are dropped, symlinks are resolved, and the result is case
/// folded on platforms whose filesystems are case-insensitive.
///
/// A path that does not exist is still normalised rather than rejected: a
/// removed worktree must still match a tab that points at it, and a worktree
/// destination the user has only just typed must still be comparable with the
/// repository it would live in. Symlink resolution therefore runs against the
/// deepest ancestor that does exist, and the segments below it are re-appended
/// verbatim. Without that, `/tmp/repo` (which exists, and on macOS resolves to
/// `/private/tmp/repo`) and `/tmp/repo/inside` (which does not) would produce
/// keys that no longer share a prefix.
///
/// Total by construction: every filesystem failure falls back to the textual
/// form, so this never throws.
String repoPathKey(String path) {
  var p = path.replaceAll('\\', '/');
  p = _stripTrailing(p);
  p = _resolveDeepestExisting(p);
  return (Platform.isMacOS || Platform.isWindows) ? p.toLowerCase() : p;
}

/// Resolves symlinks in the longest existing prefix of [p], then re-appends
/// the trailing segments that do not exist on disk. Returns [p] unchanged when
/// nothing along the way can be resolved.
String _resolveDeepestExisting(String p) {
  final missing = <String>[];
  var head = p;
  while (true) {
    try {
      final resolved = _stripTrailing(
        Directory(head).resolveSymbolicLinksSync().replaceAll('\\', '/'),
      );
      if (missing.isEmpty) return resolved;
      final tail = missing.reversed.join('/');
      return resolved.endsWith('/') ? '$resolved$tail' : '$resolved/$tail';
    } on FileSystemException {
      // This ancestor is missing or unreadable: try the one above it.
    }
    final cut = head.lastIndexOf('/');
    // No separator left (a bare relative name), or we have walked up to the
    // filesystem root without finding anything readable.
    if (cut < 0) return p;
    final leaf = head.substring(cut + 1);
    final parent = cut == 0 ? '/' : head.substring(0, cut);
    if (leaf.isEmpty || parent == head) return p;
    missing.add(leaf);
    head = parent;
  }
}

String _stripTrailing(String p) {
  var s = p;
  while (s.length > 1 && s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// True if [a] and [b] name the same directory.
bool samePath(String a, String b) => repoPathKey(a) == repoPathKey(b);
