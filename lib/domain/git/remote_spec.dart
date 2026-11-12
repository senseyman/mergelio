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

/// Whether git reaches [url] over ssh: an `ssh://` url (or `git+ssh://`,
/// `ssh+git://`) or the scp-like `[user@]host:path`. git takes the scp form
/// only when the colon comes before any slash and is not a drive letter, so
/// `./a:b` and `C:\repo` are local paths.
bool isSshRemoteUrl(String url) {
  final raw = url.trim();
  final scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://').firstMatch(raw);
  if (scheme != null) {
    return const {
      'ssh',
      'git+ssh',
      'ssh+git',
    }.contains(scheme.group(1)!.toLowerCase());
  }
  final colon = raw.indexOf(':');
  if (colon <= 0) return false;
  final slash = raw.indexOf(RegExp(r'[/\\]'));
  if (slash >= 0 && slash < colon) return false;
  return !RegExp(r'^[A-Za-z]$').hasMatch(raw.substring(0, colon));
}
