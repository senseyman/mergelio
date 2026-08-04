/// The repo-relative path a filesystem event touched, or null when the event
/// says nothing about the project tree — a path outside the repository, the
/// repository directory itself, or git's own machinery under `.git`.
///
/// Pure so the navigator's refresh scope can be reasoned about without a
/// filesystem.
String? relPathOf(String repoPath, String eventPath) {
  final repo = _normalize(repoPath);
  final event = _normalize(eventPath);
  // A sibling repository can share the whole prefix (`/r` and `/r2`), so the
  // separator has to be part of the test.
  if (!event.startsWith('$repo/')) return null;
  final rel = event.substring(repo.length + 1);
  if (rel.isEmpty) return null;
  if (rel == '.git' || rel.startsWith('.git/')) return null;
  return rel;
}

/// The repo-relative directory holding what an event touched: given an event
/// path, exactly one directory needs re-listing.
String? changedDirOf(String repoPath, String eventPath) {
  final rel = relPathOf(repoPath, eventPath);
  if (rel == null) return null;
  final cut = rel.lastIndexOf('/');
  return cut < 0 ? '' : rel.substring(0, cut);
}

/// Both separators, no trailing one — Windows reports the paths it was given,
/// which may mix the two.
String _normalize(String path) {
  final unix = path.replaceAll(r'\', '/');
  return unix.endsWith('/') ? unix.substring(0, unix.length - 1) : unix;
}
