import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/git_service.dart';
import '../domain/git/git_writer.dart';
import 'feedback.dart';
import 'repo_data.dart';
import 'undo_stack.dart';

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

  Future<void> pruneRemote(String remote) =>
      _network('Prune $remote', () => _writer.pruneRemote(remote));

  /// Fetch URL for [remote] (read-only; empty if unset).
  Future<String> remoteUrl(String remote) =>
      GitReader(_git, path).remoteUrl(remote);

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

  // --- Undoable ref operations ----------------------------------------------

  GitService get _git => _ref.read(gitServiceProvider);
  Future<String> _out(List<String> args) async =>
      (await _git.run(args, repoPath: path)).out;

  Future<String> _headSha() => _out(['rev-parse', 'HEAD']);

  /// Current branch name, or the commit sha in detached HEAD.
  Future<String> _headRef() async {
    final name = await _out(['rev-parse', '--abbrev-ref', 'HEAD']);
    return name == 'HEAD' ? await _headSha() : name;
  }

  void _toastErr(String label, GitException e) {
    final err = e.result?.err ?? '';
    _ref
        .read(toastProvider.notifier)
        .show(
          '$label failed',
          description: err.isNotEmpty ? err : e.message,
          kind: ToastKind.error,
        );
  }

  /// Runs an undoable op: executes [run], records its inverse, refreshes. The
  /// recorded undo/redo re-run real git and refresh, so the UI follows.
  Future<void> _undoable(
    String label,
    Future<void> Function() run, {
    required Future<void> Function() undo,
    required Future<void> Function() redo,
  }) async {
    if (_blockedByNetwork) return;
    // Hold the shared busy flag so a second ref op (or network op) cannot run
    // concurrently and race on .git/index.lock.
    _ref.read(busyProvider.notifier).state = BusyState(label);
    try {
      await run();
      _ref
          .read(undoProvider(path).notifier)
          .record(
            UndoEntry(
              label,
              undo: () async {
                await undo();
                _refresh();
              },
              redo: () async {
                await redo();
                _refresh();
              },
            ),
          );
      _refresh();
    } on GitException catch (e) {
      // Refresh on failure too: a conflicted cherry-pick/revert leaves the
      // repo mid-operation, which the UI must show.
      _refresh();
      _toastErr(label, e);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Resets to [prev] as part of an undo, but refuses when the working tree is
  /// dirty so an undo never silently discards uncommitted work (§9.7).
  Future<void> _undoReset(String prev) async {
    final dirty = (await _out(['status', '--porcelain'])).isNotEmpty;
    if (dirty) {
      throw GitException(
        'Uncommitted changes — commit or stash before undoing',
      );
    }
    await _writer.resetHard(prev);
  }

  /// Runs a cherry-pick/revert-style op that may conflict; on conflict it aborts
  /// (leaving a clean tree) and rethrows, since there is no in-app resolver yet.
  Future<void> _pickOrAbort(
    Future<void> Function() op,
    Future<void> Function() abort,
  ) async {
    try {
      await op();
    } on GitException {
      await abort();
      rethrow;
    }
  }

  Future<void> undo() async {
    if (_blockedByNetwork) return;
    _ref.read(busyProvider.notifier).state = const BusyState('Undo');
    try {
      await _ref.read(undoProvider(path).notifier).undo();
    } on GitException catch (e) {
      _toastErr('Undo', e);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  Future<void> redo() async {
    if (_blockedByNetwork) return;
    _ref.read(busyProvider.notifier).state = const BusyState('Redo');
    try {
      await _ref.read(undoProvider(path).notifier).redo();
    } on GitException catch (e) {
      _toastErr('Redo', e);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  Future<void> checkout(String ref) async {
    final prev = await _headRef();
    await _undoable(
      'Checkout $ref',
      () => _writer.checkout(ref),
      undo: () => _writer.checkout(prev),
      redo: () => _writer.checkout(ref),
    );
  }

  Future<void> createBranch(String name, {String? at}) async {
    // Resolve the target now so redo can recreate the branch even after undo
    // deleted it (the branch name no longer resolves at that point).
    final target = at ?? await _headSha();
    await _undoable(
      'Create branch $name',
      () => _writer.createBranch(name, at: target),
      undo: () => _writer.deleteBranch(name, force: true),
      redo: () => _writer.createBranch(name, at: target),
    );
  }

  Future<void> deleteBranch(String name) async {
    final sha = await _out(['rev-parse', name]);
    // Non-force `-d`: keep git's unmerged-branch protection so an unmerged
    // branch is not silently orphaned.
    await _undoable(
      'Delete branch $name',
      () => _writer.deleteBranch(name),
      undo: () => _writer.createBranch(name, at: sha),
      redo: () => _writer.deleteBranch(name),
    );
  }

  Future<void> renameBranch(String from, String to) => _undoable(
    'Rename $from → $to',
    () => _writer.renameBranch(from, to),
    undo: () => _writer.renameBranch(to, from),
    redo: () => _writer.renameBranch(from, to),
  );

  Future<void> setUpstream(String branch, String upstream) async {
    if (_blockedByNetwork) return;
    try {
      await _writer.setUpstream(branch, upstream);
      _refresh();
    } on GitException catch (e) {
      _toastErr('Set upstream', e);
    }
  }

  Future<void> createTag(String name, {String? at, String? message}) async {
    final target = at ?? await _headSha();
    await _undoable(
      'Create tag $name',
      () => _writer.createTag(name, at: target, message: message),
      undo: () => _writer.deleteTag(name),
      redo: () => _writer.createTag(name, at: target, message: message),
    );
  }

  Future<void> deleteTag(String name) async {
    // Dereference to the target commit: for an annotated tag `rev-parse name`
    // returns the tag object, not the commit it points at.
    final sha = await _out(['rev-parse', '$name^{commit}']);
    await _undoable(
      'Delete tag $name',
      () => _writer.deleteTag(name),
      undo: () => _writer.createTag(name, at: sha),
      redo: () => _writer.deleteTag(name),
    );
  }

  Future<void> cherryPick(String sha) async {
    final prev = await _headSha();
    await _undoable(
      'Cherry-pick ${_short(sha)}',
      () =>
          _pickOrAbort(() => _writer.cherryPick(sha), _writer.cherryPickAbort),
      undo: () => _undoReset(prev),
      redo: () =>
          _pickOrAbort(() => _writer.cherryPick(sha), _writer.cherryPickAbort),
    );
  }

  Future<void> revert(String sha) async {
    final prev = await _headSha();
    await _undoable(
      'Revert ${_short(sha)}',
      () => _pickOrAbort(() => _writer.revert(sha), _writer.revertAbort),
      undo: () => _undoReset(prev),
      redo: () => _pickOrAbort(() => _writer.revert(sha), _writer.revertAbort),
    );
  }

  Future<void> resetHard(String sha) async {
    final prev = await _headSha();
    await _undoable(
      'Reset to ${_short(sha)}',
      () => _writer.resetHard(sha),
      undo: () => _undoReset(prev),
      redo: () => _writer.resetHard(sha),
    );
  }

  Future<void> pushTag(String name) async {
    if (_blockedByNetwork) return;
    try {
      await _writer.pushTag(name);
      _ref
          .read(toastProvider.notifier)
          .show('Pushed tag $name', kind: ToastKind.success);
    } on GitException catch (e) {
      _toastErr('Push tag', e);
    }
  }

  Future<void> stashPush({String? message}) async {
    if (_blockedByNetwork) return;
    try {
      await _writer.stashPush(message: message);
      _refresh();
    } on GitException catch (e) {
      _toastErr('Stash', e);
    }
  }

  Future<void> stashApply(String ref) async {
    if (_blockedByNetwork) return;
    try {
      await _writer.stashApply(ref);
      _refresh();
    } on GitException catch (e) {
      _toastErr('Stash apply', e);
    }
  }

  Future<void> stashPop(String ref) async {
    if (_blockedByNetwork) return;
    try {
      await _writer.stashPop(ref);
      _refresh();
    } on GitException catch (e) {
      _toastErr('Stash pop', e);
    }
  }

  /// Drops a stash, offering an Undo toast that re-stores it (drop is not part
  /// of the ref undo stack because the stash index shifts).
  Future<void> stashDrop(String ref) async {
    if (_blockedByNetwork) return;
    try {
      final sha = await _writer.stashDrop(ref);
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show(
            'Dropped stash',
            action: ToastAction('Undo', () async {
              try {
                await _writer.stashStore(sha);
                _refresh();
              } on GitException catch (e) {
                _toastErr('Restore stash', e);
              }
            }),
          );
    } on GitException catch (e) {
      _toastErr('Stash drop', e);
    }
  }

  static String _short(String sha) =>
      sha.length > 7 ? sha.substring(0, 7) : sha;
}

final repoActionsProvider = Provider.family<RepoActions, String>(
  (ref, path) =>
      RepoActions(ref, path, GitWriter(ref.watch(gitServiceProvider), path)),
);
