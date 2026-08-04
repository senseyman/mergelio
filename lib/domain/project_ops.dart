import 'dart:io';

import '../core/logging.dart';
import 'file_edit.dart';

/// Windows refuses these as file names whatever the extension, and a
/// repository built on macOS or Linux still has to check out on Windows.
final _reservedNames = {
  'con',
  'prn',
  'aux',
  'nul',
  for (var i = 1; i <= 9; i++) 'com$i',
  for (var i = 1; i <= 9; i++) 'lpt$i',
};

/// Characters Windows will not accept in a name.
final _badChars = RegExp(r'[<>:"|?*\x00-\x1f]');

/// Why [name] cannot be used for a new or renamed entry, or null when it can.
/// A name is one path segment: anything that navigates is rejected here rather
/// than being resolved and checked later.
String? entryNameBlocker(String name) {
  if (name.trim().isEmpty) return 'Enter a name';
  if (name.contains('/') || name.contains(r'\')) {
    return 'A name cannot contain a path separator';
  }
  if (name == '.' || name == '..') return 'That name is reserved';
  if (name == '.git') return 'The git directory cannot be touched here';
  if (_badChars.hasMatch(name)) return 'That name contains invalid characters';
  // A trailing dot or space is silently dropped by Windows, which turns one
  // file into a different one on checkout.
  if (name.endsWith('.') || name.endsWith(' ')) {
    return 'A name cannot end with a dot or a space';
  }
  final stem = name.split('.').first.toLowerCase();
  if (_reservedNames.contains(stem)) return 'That name is reserved on Windows';
  return null;
}

/// The outcome of a filesystem operation: where it landed, or why it did not
/// happen. Failures are expected (permissions, a name already taken) and are
/// reported rather than thrown.
class ProjectOpResult {
  final bool ok;

  /// Repo-relative path the operation produced, when it succeeded.
  final String? path;
  final String? error;

  const ProjectOpResult.done(this.path) : ok = true, error = null;
  const ProjectOpResult.failed(this.error) : ok = false, path = null;
}

/// File and folder operations for one repository, as offered by the project
/// navigator. Every path is checked against the opened repository before disk
/// is touched, so a crafted name or a symlink cannot reach outside it.
class ProjectOps {
  final String repoPath;
  const ProjectOps(this.repoPath);

  Future<ProjectOpResult> createFile(String relDir, String name) =>
      _create(relDir, name, dir: false);

  Future<ProjectOpResult> createFolder(String relDir, String name) =>
      _create(relDir, name, dir: true);

  Future<ProjectOpResult> _create(
    String relDir,
    String name, {
    required bool dir,
  }) async {
    final blocker = entryNameBlocker(name);
    if (blocker != null) return ProjectOpResult.failed(blocker);
    final parent = _resolveExisting(relDir.isEmpty ? '.' : relDir);
    if (parent == null) return const ProjectOpResult.failed(_outside);
    final rel = relDir.isEmpty ? name : '$relDir/$name';
    final target = '$parent/$name';
    if (File(target).existsSync() || Directory(target).existsSync()) {
      return ProjectOpResult.failed('$name already exists here');
    }
    return _run(dir ? 'New folder $rel' : 'New file $rel', () async {
      dir
          ? await Directory(target).create()
          : await File(target).writeAsString('');
      return rel;
    });
  }

  /// Renames the entry at [relPath] to [name], keeping it in the same folder.
  Future<ProjectOpResult> rename(String relPath, String name) async {
    final blocker = entryNameBlocker(name);
    if (blocker != null) return ProjectOpResult.failed(blocker);
    final from = _resolveExisting(relPath);
    if (from == null) return const ProjectOpResult.failed(_outside);
    final cut = relPath.lastIndexOf('/');
    final relDir = cut < 0 ? '' : relPath.substring(0, cut);
    final rel = relDir.isEmpty ? name : '$relDir/$name';
    final parent = File(from).parent.path;
    final target = '$parent/$name';
    if (File(target).existsSync() || Directory(target).existsSync()) {
      return ProjectOpResult.failed('$name already exists here');
    }
    return _run('Rename $relPath to $rel', () async {
      final entity = Directory(from).existsSync()
          ? Directory(from)
          : File(from) as FileSystemEntity;
      await entity.rename(target);
      return rel;
    });
  }

  /// Removes [relPath] from disk — a directory goes with everything in it.
  Future<ProjectOpResult> delete(String relPath) async {
    final target = _resolveExisting(relPath);
    if (target == null) return const ProjectOpResult.failed(_outside);
    if (entryNameBlocker(relPath.split('/').last) != null) {
      return const ProjectOpResult.failed(_outside);
    }
    return _run('Delete $relPath', () async {
      final dir = Directory(target);
      dir.existsSync()
          ? await dir.delete(recursive: true)
          : await File(target).delete();
      return relPath;
    });
  }

  static const _outside = 'That path is not inside this repository';

  /// The absolute path [relPath] names, or null when it does not exist or
  /// resolves — through `..` or a symlink — to somewhere outside the
  /// repository.
  String? _resolveExisting(String relPath) {
    if (relPath != '.' && !isRepoRelativePath(relPath)) return null;
    if (relPath == '.git' || relPath.startsWith('.git/')) return null;
    final full = relPath == '.' ? repoPath : '$repoPath/$relPath';
    if (!File(full).existsSync() &&
        !Directory(full).existsSync() &&
        !Link(full).existsSync()) {
      return null;
    }
    return isInsideRepo(repoPath, full) ? full : null;
  }

  /// Runs [op] under the same instrumentation as every other repository
  /// action, turning a filesystem failure into a reportable result.
  Future<ProjectOpResult> _run(
    String label,
    Future<String> Function() op,
  ) async {
    try {
      return ProjectOpResult.done(
        await appLog.timed(label, op, scope: repoPath),
      );
    } on FileSystemException catch (e) {
      return ProjectOpResult.failed(e.osError?.message ?? 'Operation failed');
    }
  }
}
