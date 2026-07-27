// Validation for user-entered remote names and URLs. Runs before git so bad
// input is refused with a readable reason instead of a raw git error, and so
// a value that would be read as a command-line option never reaches git.

/// Characters git rejects in ref names; a remote name becomes part of one.
const _forbiddenNameChars = ['~', '^', ':', '?', '*', '[', '\\'];

/// Why [name] cannot be used as a remote name, or null when it is usable.
/// [existing] are the names already configured; [current] is the name of the
/// remote being edited, which may keep its own name.
String? remoteNameError(
  String name, {
  Iterable<String> existing = const [],
  String? current,
}) {
  if (name.startsWith('-')) return 'Name cannot start with a dash';
  if (name.trim().isEmpty) return 'Enter a name';
  if (RegExp(r'\s').hasMatch(name)) return 'Name cannot contain spaces';
  if (name.codeUnits.any((u) => u < 0x20 || u == 0x7f)) {
    return 'Name cannot contain control characters';
  }
  for (final c in _forbiddenNameChars) {
    if (name.contains(c)) return 'Name cannot contain $c';
  }
  if (name.contains('..')) return 'Name cannot contain ..';
  if (name.startsWith('/') || name.endsWith('/')) {
    return 'Name cannot start or end with /';
  }
  if (name.endsWith('.lock')) return 'Name cannot end with .lock';
  if (name != current && existing.contains(name)) {
    return 'A remote named $name already exists';
  }
  return null;
}

/// Why [url] cannot be used as a remote URL, or null when it is usable. Kept
/// deliberately loose: git accepts https, ssh, scp-style and local paths, and
/// rejecting an unreachable host is the network's job, not this check's.
String? remoteUrlError(String url) {
  if (url.startsWith('-')) return 'URL cannot start with a dash';
  if (url.trim().isEmpty) return 'Enter a URL';
  if (RegExp(r'\s').hasMatch(url)) return 'URL cannot contain spaces';
  if (url.codeUnits.any((u) => u < 0x20 || u == 0x7f)) {
    return 'URL cannot contain control characters';
  }
  return null;
}
