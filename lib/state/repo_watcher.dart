import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/concurrency.dart';
import '../core/logging.dart';
import '../domain/project_watch.dart';
import 'open_files.dart';
import 'project_files.dart';
import 'repo_data.dart';
import 'workspace.dart';

/// Watches the active repository's directory and refreshes its data when
/// anything changes on disk — commits, checkouts, staging or file edits made
/// outside the app (another terminal, editor, or CLI). Without this the view
/// only updated after operations the app itself performed.
///
/// The recursive watch covers both `.git` (git-state changes) and the working
/// tree (status changes); events are debounced so a burst (a checkout, a
/// fetch) triggers a single refresh once it settles. Best-effort: platforms or
/// repos where a recursive watch can't be established simply don't auto-refresh
/// (the app still works, and the app's own operations still refresh).
class RepoWatcher {
  final Ref _ref;
  StreamSubscription<FileSystemEvent>? _sub;
  RefreshCoalescer? _coalescer;
  String? _path;
  String? _trigger;

  /// Repo-relative directories touched since the last refresh. Only these are
  /// re-listed, so a save in one folder leaves the rest of an expanded tree
  /// alone.
  final _dirtyDirs = <String>{};

  RepoWatcher(this._ref) {
    _ref.listen(
      workspaceProvider.select((w) => w.activeTab?.path),
      (_, path) => _rewatch(path),
      fireImmediately: true,
    );
    _ref.onDispose(_cancel);
  }

  void _rewatch(String? path) {
    _cancel();
    _path = path;
    if (path == null) return;
    final dir = Directory(path);
    if (!dir.existsSync()) return;
    try {
      _sub = dir.watch(recursive: true).listen(
        (e) {
          if (isNoise(e.path)) return;
          _followOpenEditors(path, e);
          _schedule(path, e.path);
        },
        // Watch limits / transient FS errors must not crash the app.
        onError: (Object e) =>
            appLog.warn('repo watch error: $e', scope: 'watch'),
      );
    } on Object catch (e) {
      // No recursive watch on this platform / resource limit hit.
      appLog.warn('repo watch unavailable: $e', scope: 'watch');
    }
  }

  // High-churn paths that never affect what the UI shows — a refresh here would
  // just re-read the whole repo for nothing. Lock files under `.git` and
  // FETCH_HEAD are transients of every git command (including this app's own
  // reads and the auto-fetch): any real state change also touches the file the
  // lock protects, so ignoring them loses nothing and breaks the loop where
  // our own refresh re-triggers the watcher.
  static final _noise = RegExp(
    r'(^|/)(\.git/objects|\.git/lfs|node_modules|build|\.dart_tool|\.gradle|target|dist|\.next)(/|$)'
    r'|(^|/)\.git/(.+\.lock|FETCH_HEAD)$',
  );

  @visibleForTesting
  static bool isNoise(String path) => _noise.hasMatch(path);

  /// 500ms trailing: coalesces editor save-storms and long git operations into
  /// a single refresh once things settle. A refresh is also held back while the
  /// previous read is still running, so a repository that takes longer to read
  /// than the burst takes to arrive cannot accumulate overlapping reads.
  RefreshCoalescer _coalescerFor(String path) => RefreshCoalescer(
    settle: const Duration(milliseconds: 500),
    busy: () => _ref.read(repoDataProvider(path)).isLoading,
    onRefresh: () {
      if (_path != path) return;
      // Names the file that caused the refresh: a repository that reloads in a
      // loop is diagnosed from these lines.
      appLog.info('refresh of $path triggered by $_trigger', scope: 'watch');
      _ref.invalidate(repoDataProvider(path));
      _refreshDirtyDirs(path);
    },
  );

  /// Drops the cached listing, ignore state and tracked set for what changed.
  /// Files mode reads these lazily, so an unopened directory pays nothing.
  void _refreshDirtyDirs(String path) {
    if (_dirtyDirs.isEmpty) return;
    for (final dir in _dirtyDirs) {
      final key = DirKey(path, dir);
      _ref.invalidate(dirListingProvider(key));
      _ref.invalidate(ignoredInDirProvider(key));
    }
    _dirtyDirs.clear();
    // A new or removed file changes what git tracks, and that set is per
    // repository rather than per directory.
    _ref.invalidate(trackedPathsProvider(path));
  }

  /// Keeps open editors pointing at the right file when something moves or
  /// removes it from underneath them. Paths nothing has open are ignored by
  /// the notifier, so this costs a lookup and nothing more.
  void _followOpenEditors(String repoPath, FileSystemEvent e) {
    final rel = relPathOf(repoPath, e.path);
    if (rel == null) return;
    final files = _ref.read(openFilesProvider(repoPath).notifier);
    if (e is FileSystemMoveEvent) {
      final to = e.destination == null
          ? null
          : relPathOf(repoPath, e.destination!);
      // A move out of the repository is a disappearance as far as the tab is
      // concerned.
      to == null ? files.markGone(rel) : files.rename(rel, to);
      return;
    }
    e.type == FileSystemEvent.delete
        ? files.markGone(rel)
        : files.markPresent(rel);
  }

  void _schedule(String path, String trigger) {
    _trigger = trigger;
    final dir = changedDirOf(path, trigger);
    if (dir != null) _dirtyDirs.add(dir);
    _coalescer ??= _coalescerFor(path);
    _coalescer!.schedule();
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
    _coalescer?.cancel();
    _coalescer = null;
    // Directories belong to the repository being left behind.
    _dirtyDirs.clear();
  }

  /// Force an immediate refresh of the active repo (e.g. on window focus).
  void refreshNow() {
    final path = _path;
    if (path != null) _ref.invalidate(repoDataProvider(path));
  }
}

/// Kept alive by the app shell for the app's lifetime.
final repoWatcherProvider = Provider<RepoWatcher>(RepoWatcher.new);
