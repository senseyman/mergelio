/// LFS pointer file parsing: extract the content identifier and size.
/// Nothing here runs git, touches the filesystem, or networks.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

/// The version line every LFS pointer opens with.
const lfsPointerVersion = 'version https://git-lfs.github.com/spec/v1';

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
    if (!_keyName.hasMatch(key)) return null;
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
bool supportsCheckAttrSource(String gitVersion) {
  final m = _gitVersion.firstMatch(gitVersion);
  if (m == null) return false;
  final major = int.parse(m.group(1)!);
  final minor = int.parse(m.group(2)!);
  return major > 2 || (major == 2 && minor >= 40);
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

final _batchHeader = RegExp(r'^(\S+) \S+ (\d+)$');

/// `git cat-file --batch` output → content by object id. Record sizes are in
/// bytes, so the walk happens over UTF-8 bytes. A header that does not parse
/// ends the walk: everything after it would be misaligned.
Map<String, String> parseCatFileBatch(String raw) {
  final bytes = utf8.encode(raw);
  final out = <String, String>{};
  var at = 0;
  while (at < bytes.length) {
    final eol = bytes.indexOf(0x0a, at);
    if (eol < 0) break;
    final m = _batchHeader.firstMatch(utf8.decode(bytes.sublist(at, eol)));
    if (m == null) break;
    final size = int.parse(m.group(2)!);
    final start = eol + 1;
    if (start + size > bytes.length) break;
    out[m.group(1)!] = utf8.decode(
      bytes.sublist(start, start + size),
      allowMalformed: true,
    );
    at = start + size + 1; // content is followed by a newline
  }
  return out;
}
