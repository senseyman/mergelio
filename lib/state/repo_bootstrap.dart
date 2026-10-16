import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../domain/git/askpass.dart';
import '../domain/git/clone_options.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_service.dart';
import '../l10n/gen/app_localizations.dart';
import 'feedback.dart';
import 'l10n.dart';
import 'recents.dart';
import 'workspace.dart';

/// Gets repositories into the app: clone from a URL or create a new local one.
/// On success the repo opens as a tab and lands in recents; failures surface
/// as an error toast and return null.
class RepoBootstrap {
  final Ref _ref;
  RepoBootstrap(this._ref);

  GitService get _git => _ref.read(gitServiceProvider);
  AppLocalizations get _l => _ref.read(appL10nProvider);

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

  /// Whether joining [name] onto [parentDir] yields a path inside [parentDir].
  /// `join` discards the parent entirely when [name] is absolute (including
  /// drive-letter paths on Windows), so containment must be checked on the
  /// joined result. Lexical only; [parentDir] is expected to be absolute.
  /// [context] defaults to the host platform and lets tests exercise Windows
  /// path rules from any host.
  static bool staysInsideParent(
    String parentDir,
    String name, {
    p.Context? context,
  }) {
    final ctx = context ?? p.context;
    final target = ctx.normalize(ctx.join(parentDir, name));
    return ctx.isWithin(ctx.normalize(parentDir), target);
  }

  /// Clones [url] into `[parentDir]/[folderName]` with [options] and opens it.
  /// Long timeout — clones legitimately take minutes on big repos. Returns the
  /// new repo path.
  Future<String?> clone({
    required String url,
    required String parentDir,
    String? folderName,
    CloneOptions options = const CloneOptions(),
  }) async {
    final name = (folderName == null || folderName.trim().isEmpty)
        ? folderNameFromUrl(url)
        : folderName.trim();
    if (url.trim().isEmpty || parentDir.isEmpty || name.isEmpty) {
      _toast(_l.actFailed(_l.bootClone), _l.bootUrlDestRequired);
      return null;
    }
    switch (options.problem) {
      case CloneProblem.badDepth:
        _toast(_l.actFailed(_l.bootClone), _l.bootBadDepth);
        return null;
      case CloneProblem.badBranch:
        _toast(_l.actFailed(_l.bootClone), _l.bootBadBranch);
        return null;
      case null:
    }
    // Reject folder names that could escape the parent via .. segments.
    if (name.contains('..') || name.startsWith('/') || name.startsWith(r'\')) {
      _toast(_l.actFailed(_l.bootClone), _l.bootBadFolder);
      return null;
    }
    if (!staysInsideParent(parentDir, name)) {
      _toast(_l.actFailed(_l.bootClone), _l.bootOutsideParent);
      return null;
    }
    final target = p.join(parentDir, name);
    final destinationExisted = Directory(target).existsSync();
    if (destinationExisted && Directory(target).listSync().isNotEmpty) {
      _toast(_l.actFailed(_l.bootClone), _l.bootDestExists(target));
      return null;
    }
    // Handed to the progress bar so a clone stalled on an unreachable host can
    // be given up on, instead of holding the app for the whole 15 minutes.
    final cancel = GitCancel();
    _ref.read(busyProvider.notifier).state = BusyState(
      _l.bootClone,
      onCancel: cancel.cancel,
    );
    try {
      final r = await _git.run(
        cloneArgs(url.trim(), target, options),
        timeout: const Duration(minutes: 15),
        // No repository exists yet, so this reads the global and system config
        // for the ssh command the user set.
        environment: await resolveNetworkEnv(
          _git,
          askpass: askpassHelper,
          askpassRepo: target,
        ),
        cancel: cancel,
      );
      if (!r.ok) {
        _toast(_l.actFailed(_l.bootClone), r.err);
        await _discardPartialClone(target, keepDirectory: destinationExisted);
        return null;
      }
      _open(name, target);
      return target;
    } on GitCancelledException {
      _ref
          .read(toastProvider.notifier)
          .show(_l.actCancelled(_l.bootClone), kind: ToastKind.warning);
      await _discardPartialClone(target, keepDirectory: destinationExisted);
      return null;
    } on GitException catch (e) {
      _toast(_l.actFailed(_l.bootClone), e.result?.err ?? e.message);
      await _discardPartialClone(target, keepDirectory: destinationExisted);
      return null;
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Clears out what a failed or abandoned clone left behind, so the next
  /// attempt is not refused for a destination that already exists. The
  /// destination was verified empty beforehand, so everything in it now came
  /// from the clone. [keepDirectory] holds on to a folder the user had already
  /// made — only its contents are ours to remove.
  Future<void> _discardPartialClone(
    String target, {
    required bool keepDirectory,
  }) async {
    try {
      final dir = Directory(target);
      if (!dir.existsSync()) return;
      if (keepDirectory) {
        for (final entry in dir.listSync()) {
          await entry.delete(recursive: true);
        }
      } else {
        await dir.delete(recursive: true);
      }
    } on Object catch (e) {
      debugPrint('bootstrap: partial clone cleanup failed: $e');
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
      _toast(_l.actFailed(_l.bootCreate), _l.bootNameFolderRequired);
      return null;
    }
    final trimmed = name.trim();
    // Reject names that could escape the parent via .. segments.
    if (trimmed.contains('..') ||
        trimmed.startsWith('/') ||
        trimmed.startsWith(r'\')) {
      _toast(_l.actFailed(_l.bootCreate), _l.bootBadFolder);
      return null;
    }
    if (!staysInsideParent(parentDir, trimmed)) {
      _toast(_l.actFailed(_l.bootCreate), _l.bootOutsideParent);
      return null;
    }
    final target = p.join(parentDir, trimmed);
    if (Directory(target).existsSync() &&
        Directory(target).listSync().isNotEmpty) {
      _toast(_l.actFailed(_l.bootCreate), _l.bootFolderExists(target));
      return null;
    }
    _ref.read(busyProvider.notifier).state = BusyState(_l.bootCreate);
    try {
      await Directory(target).create(recursive: true);
      final init = await _git.run(['init', '-b', defaultBranch, target]);
      if (!init.ok) {
        _toast(_l.actFailed(_l.bootCreate), init.err);
        return null;
      }
      final files = <String>[];
      if (readme) {
        await File(p.join(target, 'README.md'))
            .writeAsString('# ${name.trim()}\n');
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
        if (!c.ok) _toast(_l.bootInitialCommitFailed, c.err);
      }
      _open(name.trim(), target);
      return target;
    } on GitException catch (e) {
      _toast(_l.actFailed(_l.bootCreate), e.result?.err ?? e.message);
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
