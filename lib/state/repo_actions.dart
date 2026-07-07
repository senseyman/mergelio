import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_service.dart';
import '../domain/git/git_writer.dart';
import 'feedback.dart';
import 'repo_data.dart';

/// Mutating git operations for one repo, each followed by a refresh of
/// [repoDataProvider] so the graph, counts and file lists update in lockstep.
class RepoActions {
  final Ref _ref;
  final String path;
  final GitWriter _writer;
  RepoActions(this._ref, this.path, this._writer);

  void _refresh() => _ref.invalidate(repoDataProvider(path));

  /// Runs a network op behind the top progress bar, refreshes on success and
  /// toasts the outcome. Errors never escape — they surface as a toast.
  Future<void> _network(String label, Future<void> Function() op) async {
    final toasts = _ref.read(toastProvider.notifier);
    _ref.read(busyProvider.notifier).state = BusyState(label);
    try {
      await op();
      toasts.show('$label complete', kind: ToastKind.success);
    } on GitException catch (e) {
      // Prefer git's own stderr; fall back to the short message.
      final err = e.result?.err ?? '';
      toasts.show(
        '$label failed',
        description: err.isNotEmpty ? err : e.message,
        kind: ToastKind.error,
      );
    } on Object catch (_) {
      toasts.show(
        '$label failed',
        description: 'Unexpected error',
        kind: ToastKind.error,
      );
    } finally {
      // Refresh even on failure: a failed pull/merge can still leave the repo
      // mid-operation (conflicts, MERGING) that the UI must show.
      _refresh();
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  Future<void> fetch({String? remote}) =>
      _network('Fetch', () => _writer.fetch(remote: remote));

  Future<void> pull({bool rebase = false}) =>
      _network('Pull', () => _writer.pull(rebase: rebase));

  Future<void> push({bool force = false}) =>
      _network(force ? 'Force push' : 'Push', () => _writer.push(force: force));

  /// True (and toasts) when a network op holds the repo, so an index-touching
  /// mutation must not run concurrently and race on `.git/index.lock`.
  bool get _blockedByNetwork {
    if (_ref.read(busyProvider) == null) return false;
    _ref
        .read(toastProvider.notifier)
        .show('An operation is already running', kind: ToastKind.warning);
    return true;
  }

  Future<void> stageFile(String p) async {
    if (_blockedByNetwork) return;
    await _writer.stageFile(p);
    _refresh();
  }

  Future<void> unstageFile(String p) async {
    if (_blockedByNetwork) return;
    await _writer.unstageFile(p);
    _refresh();
  }

  Future<void> stageAll() async {
    if (_blockedByNetwork) return;
    await _writer.stageAll();
    _refresh();
  }

  Future<void> unstageAll() async {
    if (_blockedByNetwork) return;
    await _writer.unstageAll();
    _refresh();
  }

  Future<void> applyPatch(String patch, {bool reverse = false}) async {
    if (_blockedByNetwork) return;
    await _writer.applyToIndex(patch, reverse: reverse);
    _refresh();
  }

  Future<void> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    List<String> coauthors = const [],
  }) async {
    if (_blockedByNetwork) return;
    await _writer.commit(
      summary,
      description: description,
      amend: amend,
      sign: sign,
      coauthors: coauthors,
    );
    _refresh();
  }
}

final repoActionsProvider = Provider.family<RepoActions, String>(
  (ref, path) =>
      RepoActions(ref, path, GitWriter(ref.watch(gitServiceProvider), path)),
);
