import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../domain/git/git_providers.dart';
import '../domain/git/git_service.dart';
import 'feedback.dart';
import 'recents.dart';
import 'workspace.dart';

/// Gets repositories into the app: clone from a URL or create a new local one.
/// On success the repo opens as a tab and lands in recents; failures surface
/// as an error toast and return null.
class RepoBootstrap {
  final Ref _ref;
  RepoBootstrap(this._ref);

  GitService get _git => _ref.read(gitServiceProvider);

  /// The folder a clone of [url] would produce: the last path segment minus a
  /// trailing `.git`. Handles https, ssh (user@host:org/repo.git) and local
  /// paths; empty when nothing sensible can be derived.
  static String folderNameFromUrl(String url) {
    var s = url.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'/+$'), '');
    // ssh scp-like syntax: user@host:org/repo.git
    final colon = s.indexOf(':');
    if (!s.contains('://') && colon > 0) s = s.substring(colon + 1);
    var name = s.split('/').last;
    if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
    return name;
  }

  /// Clones [url] into `[parentDir]/[folderName]` and opens it. Long timeout —
  /// clones legitimately take minutes on big repos. Returns the new repo path.
  Future<String?> clone({
    required String url,
    required String parentDir,
    String? folderName,
  }) async {
    final name = (folderName == null || folderName.trim().isEmpty)
        ? folderNameFromUrl(url)
        : folderName.trim();
    if (url.trim().isEmpty || parentDir.isEmpty || name.isEmpty) {
      _toast('Clone failed', 'URL and destination are required');
      return null;
    }
    final target = p.join(parentDir, name);
    if (Directory(target).existsSync() &&
        Directory(target).listSync().isNotEmpty) {
      _toast('Clone failed', 'Destination already exists: $target');
      return null;
    }
    _ref.read(busyProvider.notifier).state = const BusyState('Clone');
    try {
      final r = await _git.run([
        'clone',
        url.trim(),
        target,
      ], timeout: const Duration(minutes: 15));
      if (!r.ok) {
        _toast('Clone failed', r.err);
        return null;
      }
      _open(name, target);
      return target;
    } on GitException catch (e) {
      _toast('Clone failed', e.result?.err ?? e.message);
      return null;
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Creates `[parentDir]/[name]`: `git init -b [defaultBranch]`, optional
  /// README / .gitignore committed as the initial commit. Returns the path.
  Future<String?> create({
    required String name,
    required String parentDir,
    String defaultBranch = 'main',
    bool readme = true,
    bool gitignore = false,
  }) async {
    if (name.trim().isEmpty || parentDir.isEmpty) {
      _toast('Create failed', 'Name and folder are required');
      return null;
    }
    final target = p.join(parentDir, name.trim());
    if (Directory(target).existsSync() &&
        Directory(target).listSync().isNotEmpty) {
      _toast('Create failed', 'Folder already exists: $target');
      return null;
    }
    _ref.read(busyProvider.notifier).state = const BusyState('Create');
    try {
      await Directory(target).create(recursive: true);
      final init = await _git.run(['init', '-b', defaultBranch, target]);
      if (!init.ok) {
        _toast('Create failed', init.err);
        return null;
      }
      final files = <String>[];
      if (readme) {
        await File(
          p.join(target, 'README.md'),
        ).writeAsString('# ${name.trim()}\n');
        files.add('README.md');
      }
      if (gitignore) {
        await File(p.join(target, '.gitignore')).writeAsString('');
        files.add('.gitignore');
      }
      if (files.isNotEmpty) {
        await _git.run(['add', ...files], repoPath: target);
        final c = await _git.run([
          'commit',
          '-m',
          'Initial commit',
        ], repoPath: target);
        // A missing user.name/email makes the initial commit fail; the repo
        // itself is still created and usable, so only warn.
        if (!c.ok) _toast('Initial commit failed', c.err);
      }
      _open(name.trim(), target);
      return target;
    } on GitException catch (e) {
      _toast('Create failed', e.result?.err ?? e.message);
      return null;
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  void _open(String name, String path) {
    _ref.read(workspaceProvider.notifier).openRepo(path, name: name);
    // Recents are best-effort: never fail the flow over the MRU list.
    try {
      _ref.read(recentsProvider.notifier).add(name, path);
    } on Object catch (e) {
      debugPrint('bootstrap: recents add failed: $e');
    }
  }

  void _toast(String title, String description) => _ref
      .read(toastProvider.notifier)
      .show(title, description: description, kind: ToastKind.error);
}

final repoBootstrapProvider = Provider<RepoBootstrap>(RepoBootstrap.new);
