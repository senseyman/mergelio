import 'package:path/path.dart' as p;

/// How much an ignore rule written for one file covers.
enum IgnoreScope {
  /// Just that file.
  file,

  /// Every file sharing its extension, at any depth.
  extension,

  /// The whole folder the file sits in.
  folder,
}

/// Which ignore file a rule is appended to.
enum IgnoreTarget {
  /// The `.gitignore` at the repository root.
  root,

  /// The closest `.gitignore` above the file, below the root.
  nearest,

  /// `.git/info/exclude`: local to this clone, never committed.
  exclude,
}

/// The line that ignores [relPath] at [scope], for an ignore file in the
/// repo-relative directory [baseDir] (empty for the root and for
/// `info/exclude`). Null when no rule fits: no extension, a file directly in
/// [baseDir] asked to ignore its folder, a path outside [baseDir], or a path a
/// single line cannot hold.
String? ignoreRule(String relPath, IgnoreScope scope, {String baseDir = ''}) {
  if (relPath.isEmpty || relPath.contains('\n') || relPath.contains('\r')) {
    return null;
  }
  final String rel;
  if (baseDir.isEmpty) {
    rel = relPath;
  } else {
    if (!relPath.startsWith('$baseDir/')) return null;
    rel = relPath.substring(baseDir.length + 1);
  }
  switch (scope) {
    case IgnoreScope.file:
      // Anchored so only this path matches; the slash also keeps a leading
      // `#` or `!` from reading as a comment or a negation.
      return '/${_escape(rel)}';
    case IgnoreScope.extension:
      final ext = p.posix.extension(p.posix.basename(rel));
      return ext.isEmpty ? null : '*${_escape(ext)}';
    case IgnoreScope.folder:
      final dir = p.posix.dirname(rel);
      return dir == '.' ? null : '/${_escape(dir)}/';
  }
}

/// Escapes what gitignore would otherwise read as a glob, plus trailing
/// spaces, which git strips unless quoted.
String _escape(String s) {
  final globbed = s.replaceAllMapped(RegExp(r'[\\*?\[]'), (m) => '\\${m[0]}');
  final trimmed = globbed.trimRight();
  final trailing = globbed.length - trimmed.length;
  return trimmed + r'\ ' * trailing;
}

/// [existing] with [rule] appended as its own line, or null when that exact
/// line is already there. Nothing before it changes; a missing final newline
/// is added so the rule does not join the last line.
String? appendIgnoreRule(String existing, String rule) {
  // Only a CRLF ending is dropped: a rule can end in an escaped space.
  final lines = existing
      .split('\n')
      .map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l);
  if (lines.contains(rule)) return null;
  final sep = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
  return '$existing$sep$rule\n';
}

/// The directories holding [relPath], closest first, without the root.
List<String> ancestorDirs(String relPath) {
  final dirs = <String>[];
  for (var d = p.posix.dirname(relPath); d != '.'; d = p.posix.dirname(d)) {
    dirs.add(d);
  }
  return dirs;
}
