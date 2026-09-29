/// LFS pointer file parsing: extract the content identifier and size.
/// Nothing here runs git, touches the filesystem, or networks.
library;

import 'dart:convert';
import 'dart:math' show max;

import 'package:path/path.dart' as p;

/// The version line every LFS pointer opens with.
const lfsPointerVersion = 'version https://git-lfs.github.com/spec/v1';

/// Matches a `.gitattributes` line that routes files through LFS, as an
/// extended regex for `git grep -E`. Text after `#` is a comment to git, so a
/// line that only mentions the filter there does not count.
const lfsAttributePattern = r'^[^#]*filter=lfs';

/// Pointers are tiny by definition; anything bigger is real content that
/// merely looks like one.
const lfsPointerMaxBytes = 1024;

/// What a pointer file says about the content it stands in for.
class LfsPointer {
  /// Lowercase hex sha256 of the real content, without the `sha256:` prefix.
  final String oid;
  final int size;
  const LfsPointer({required this.oid, required this.size});

  @override
  bool operator ==(Object other) =>
      other is LfsPointer && other.oid == oid && other.size == size;

  @override
  int get hashCode => Object.hash(oid, size);
}

final _oidValue = RegExp(r'^sha256:([0-9a-f]{64})$');
final _sizeValue = RegExp(r'^(0|[1-9][0-9]*)$');
final _keyName = RegExp(r'^[a-z0-9.-]+$');

/// Parses [text] as a pointer, returning null for anything else.
///
/// Strict on purpose: a loose match would turn an ordinary small text file
/// that happens to mention the spec into an "LFS object" and hide its
/// real diff.
LfsPointer? parseLfsPointer(String text) {
  // UTF-16 units never outnumber UTF-8 bytes, so this cheap check rejects
  // big files before any encoding work.
  if (text.length > lfsPointerMaxBytes) return null;
  if (utf8.encode(text).length > lfsPointerMaxBytes) return null;
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  if (lines.isEmpty || lines.first != lfsPointerVersion) return null;

  String? oid;
  int? size;
  String? previousKey;

  for (final line in lines.skip(1)) {
    final space = line.indexOf(' ');
    if (space <= 0) return null;
    final key = line.substring(0, space);
    final value = line.substring(space + 1);
    if (!_keyName.hasMatch(key) || key == 'version') return null;
    // Keys must be in sorted order.
    if (previousKey != null && key.compareTo(previousKey) <= 0) return null;
    previousKey = key;
    switch (key) {
      case 'oid':
        oid = _oidValue.firstMatch(value)?.group(1);
        if (oid == null) return null;
      case 'size':
        if (!_sizeValue.hasMatch(value)) return null;
        size = int.tryParse(value);
        if (size == null) return null;
    }
  }
  if (oid == null || size == null) return null;
  return LfsPointer(oid: oid, size: size);
}

/// Paths whose `filter` attribute is `lfs`, from `git check-attr -z filter`
/// output: `path NUL attribute NUL value NUL`, repeated.
Set<String> parseCheckAttrLfs(String raw) {
  final fields = raw.split('\x00');
  return {
    for (var i = 0; i + 2 < fields.length; i += 3)
      if (fields[i + 1] == 'filter' && fields[i + 2] == 'lfs') fields[i],
  };
}

final _lfsVersion = RegExp(r'^git-lfs/(\d+\.\d+\.\d+)');

/// `git lfs version` output → `3.5.1`, or null when git-lfs did not answer.
String? parseLfsVersion(String out) =>
    _lfsVersion.firstMatch(out.trim())?.group(1);

final _gitVersion = RegExp(r'git version (\d+)\.(\d+)');

/// Whether `git check-attr --source` exists, which is what lets a commit's
/// own attributes answer for it. Added in git 2.40.
bool supportsCheckAttrSource(String gitVersion) => _atLeast(gitVersion, 2, 40);

/// The arguments that name [rev] to a git command that also takes options,
/// or null when that cannot be done safely.
///
/// A revision can be a branch named like an option (`-Osh` makes `git grep`
/// run `sh` on every match). From git 2.24, `--end-of-options` keeps it a
/// revision. Older git has no such marker, so a revision starting with `-`
/// is refused there rather than passed where git would read it as a flag.
List<String>? revisionArgs(String rev, String gitVersion) {
  if (_atLeast(gitVersion, 2, 24)) return ['--end-of-options', rev];
  if (rev.startsWith('-')) return null;
  return [rev];
}

bool _atLeast(String gitVersion, int major, int minor) {
  final m = _gitVersion.firstMatch(gitVersion);
  if (m == null) return false;
  final gotMajor = int.parse(m.group(1)!);
  final gotMinor = int.parse(m.group(2)!);
  return gotMajor > major || (gotMajor == major && gotMinor >= minor);
}

/// Where downloaded LFS objects live. [commonDir] is `git rev-parse
/// --git-common-dir` (relative to [repoPath] when not absolute), so linked
/// worktrees share one store. [lfsStorage] is the `lfs.storage` setting, which
/// git-lfs resolves against the git directory when relative.
String lfsObjectsDir({
  required String repoPath,
  required String commonDir,
  String? lfsStorage,
}) {
  final common = p.isAbsolute(commonDir)
      ? commonDir
      : p.join(repoPath, commonDir);
  final storage = lfsStorage == null || lfsStorage.isEmpty
      ? p.join(common, 'lfs')
      : p.isAbsolute(lfsStorage)
      ? lfsStorage
      : p.join(common, lfsStorage);
  return p.normalize(p.join(storage, 'objects'));
}

/// The file an object with [oid] is stored at, once downloaded.
String lfsObjectPath(String objectsDir, String oid) =>
    p.join(objectsDir, oid.substring(0, 2), oid.substring(2, 4), oid);

/// Human size: whole bytes below a kilobyte, one decimal above.
String formatLfsSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  // Compare after rounding, so 1023.96 KB reads as 1.0 MB rather than
  // 1024.0 KB.
  while (unit < units.length - 1 && (value * 10).round() >= 10240) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// How git-lfs is usually obtained on each platform.
enum LfsInstallRoute { homebrew, gitForWindows, packageManager }

LfsInstallRoute lfsInstallRoute(String operatingSystem) =>
    switch (operatingSystem) {
      'macos' => LfsInstallRoute.homebrew,
      'windows' => LfsInstallRoute.gitForWindows,
      _ => LfsInstallRoute.packageManager,
    };

/// `git grep -l -z ... <rev>` output → paths, without the `<rev>:` prefix git
/// puts on every match when grepping a revision.
Set<String> parseGrepRevPaths(String raw, String rev) {
  final prefix = '$rev:';
  return {
    for (final entry in raw.split('\x00'))
      if (entry.startsWith(prefix)) entry.substring(prefix.length),
  };
}

/// `git cat-file --batch-check` output, one entry per input line in the same
/// order: the blob's id and size, or null when the object is missing or is
/// not a blob.
List<(String, int)?> parseBatchCheck(String raw) {
  final lines = raw.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return [
    for (final line in lines)
      switch (line.split(' ')) {
        [final oid, 'blob', final size] when int.tryParse(size) != null => (
          oid,
          int.parse(size),
        ),
        _ => null,
      },
  ];
}

/// `git cat-file --batch` output → content by object id, matched against
/// [order] — the oids requested, in the order git answers them.
///
/// A record's declared byte count cannot be used to slice the raw string:
/// the caller already decoded stdout with malformed bytes replaced, and a
/// replaced byte does not take up the same number of code units as the byte
/// it stood in for, so a count-based walk desyncs the moment one appears.
/// Each record's end is found instead by locating where the next expected
/// oid's header begins.
Map<String, String> parseCatFileBatch(String raw, List<String> order) {
  final out = <String, String>{};
  var pos = 0;
  for (var i = 0; i < order.length; i++) {
    final oid = order[i];
    if (!raw.startsWith('$oid ', pos)) break;
    final headerEnd = raw.indexOf('\n', pos);
    if (headerEnd < 0) break;
    final contentStart = headerEnd + 1;
    final int contentEnd;
    if (i + 1 < order.length) {
      final next = raw.indexOf('\n${order[i + 1]} ', contentStart);
      if (next < 0) break;
      contentEnd = next;
    } else {
      contentEnd = raw.endsWith('\n') ? raw.length - 1 : raw.length;
    }
    out[oid] = raw.substring(contentStart, contentEnd);
    pos = contentEnd + 1;
  }
  return out;
}

/// One file `git lfs ls-files -l` reports: its object, its path, and whether
/// the working-tree file holds the content (`*`) or is still a pointer (`-`).
class LfsLsEntry {
  final String oid;
  final String path;
  final bool checkedOut;
  const LfsLsEntry({
    required this.oid,
    required this.path,
    required this.checkedOut,
  });

  @override
  bool operator ==(Object other) =>
      other is LfsLsEntry &&
      other.oid == oid &&
      other.path == path &&
      other.checkedOut == checkedOut;

  @override
  int get hashCode => Object.hash(oid, path, checkedOut);
}

final _lsFilesLine = RegExp(r'^([0-9a-f]{64}) ([*-]) (.+)$');

/// `git lfs ls-files -l` output → entries. Anything else on the stream
/// (warnings, blank lines) is skipped. CRLF endings are accepted, since
/// git-lfs writes the line endings of the platform it runs on.
List<LfsLsEntry> parseLfsLsFiles(String raw) => [
  for (final line in _lines(raw))
    if (_lsFilesLine.firstMatch(line) case final m?)
      LfsLsEntry(oid: m[1]!, path: m[3]!, checkedOut: m[2] == '*'),
];

/// What `git lfs prune --dry-run --verbose` would remove: how many objects.
/// There is no byte total — git-lfs prints at most one ` * <oid> (<size>)`
/// detail line regardless of how many objects it actually prunes, so no
/// per-object size is available to sum.
class LfsPrunePreview {
  final int count;
  const LfsPrunePreview({required this.count});

  @override
  bool operator ==(Object other) =>
      other is LfsPrunePreview && other.count == count;

  @override
  int get hashCode => count.hashCode;
}

final _pruneSummary = RegExp(r'^(\d+) local objects?, (\d+) retained');

/// The dry run's report, or null when it does not look like one. Null and
/// "nothing to prune" are different answers: only the second may be shown as
/// such, and neither may lead to a prune.
///
/// The count is the summary line's `local − retained` difference, never
/// below zero. Detail lines cannot be counted instead: git-lfs shows at most
/// one of them no matter how many objects it prunes.
LfsPrunePreview? parseLfsPruneDryRun(String raw) {
  for (final line in _lines(raw)) {
    final m = _pruneSummary.firstMatch(line.trim());
    if (m == null) continue;
    final local = int.parse(m[1]!);
    final retained = int.parse(m[2]!);
    return LfsPrunePreview(count: max(0, local - retained));
  }
  return null;
}

/// Splits git-lfs output into lines, dropping CRLF's `\r`: git-lfs's line
/// endings follow the platform it ran on, not the platform reading them.
List<String> _lines(String raw) => raw.replaceAll('\r\n', '\n').split('\n');

/// A pattern `git lfs track` lists, and the `.gitattributes` it lives in.
class LfsTrackedPattern {
  final String pattern;
  final String source;
  const LfsTrackedPattern({required this.pattern, required this.source});

  @override
  bool operator ==(Object other) =>
      other is LfsTrackedPattern &&
      other.pattern == pattern &&
      other.source == source;

  @override
  int get hashCode => Object.hash(pattern, source);
}

final _trackLine = RegExp(r'^\s+(.+) \(([^()]+)\)$');

/// `git lfs track` (no arguments) → the tracked patterns. Excluded patterns,
/// listed after them, are not tracked and are left out.
List<LfsTrackedPattern> parseLfsTrackList(String raw) {
  final out = <LfsTrackedPattern>[];
  var inTracked = false;
  for (final line in _lines(raw)) {
    if (line.startsWith('Listing tracked patterns')) {
      inTracked = true;
    } else if (line.startsWith('Listing ')) {
      inTracked = false;
    } else if (inTracked) {
      final m = _trackLine.firstMatch(line);
      if (m != null) out.add(LfsTrackedPattern(pattern: m[1]!, source: m[2]!));
    }
  }
  return out;
}

/// Whether a `pre-push` hook hands the push to git-lfs, which is what
/// uploads the objects the pushed commits point at.
bool isLfsPrePushHook(String hookText) =>
    hookText.contains('git lfs pre-push') ||
    hookText.contains('git-lfs pre-push');

/// Whether [path] can be passed to `--include` as itself. The option takes
/// comma-separated glob patterns, so these characters would change its
/// meaning rather than be matched.
bool lfsIncludeSafe(String path) => !RegExp(r'[,*?\[\]\\]').hasMatch(path);

/// `*.<ext>` for [path]'s extension, or null when it has none that can be
/// written as a pattern without escaping.
String? lfsExtensionPattern(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  final ext = name.substring(dot + 1);
  if (!RegExp(r'^[A-Za-z0-9_+-]+$').hasMatch(ext)) return null;
  return '*.$ext';
}
