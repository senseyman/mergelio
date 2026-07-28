import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/concurrency.dart';
import '../core/logging.dart';
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
          if (!_isNoise(e.path)) _schedule(path, e.path);
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
  // just re-read the whole repo for nothing.
  static final _noise = RegExp(
    r'(^|/)(\.git/objects|\.git/lfs|node_modules|build|\.dart_tool|\.gradle|target|dist|\.next)(/|$)',
  );
  static bool _isNoise(String path) => _noise.hasMatch(path);

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
    },
  );

  void _schedule(String path, String trigger) {
    _trigger = trigger;
    _coalescer ??= _coalescerFor(path);
    _coalescer!.schedule();
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
    _coalescer?.cancel();
    _coalescer = null;
  }

  /// Force an immediate refresh of the active repo (e.g. on window focus).
  void refreshNow() {
    final path = _path;
    if (path != null) _ref.invalidate(repoDataProvider(path));
  }
}

/// Kept alive by the app shell for the app's lifetime.
final repoWatcherProvider = Provider<RepoWatcher>(RepoWatcher.new);
