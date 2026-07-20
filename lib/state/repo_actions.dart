import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/conflict.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/git_service.dart';
import '../domain/git/git_writer.dart';
import '../domain/git/models.dart';
import '../domain/git/rebase_plan.dart';
import 'feedback.dart';
import 'merge_session.dart';
import 'operation_journal.dart';
import 'profiles.dart';
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

  // Crash-safe journal: write a durable pending marker before a mutation runs,
  // then mark it done/failed. A marker still pending on the next launch means
  // the process died mid-op. Best-effort — journaling must never break an op.
  OperationJournal get _journal => _ref.read(operationJournalProvider(path));

  Future<int?> _journalBegin(String label) async {
    try {
      return await _journal.begin(label, DateTime.now().toIso8601String());
    } on Object {
      return null;
    }
  }

  Future<void> _journalDone(int? id) async {
    if (id == null) return;
    try {
      await _journal.complete(id);
    } on Object {
      /* ignore */
    }
  }

  Future<void> _journalFail(int? id) async {
    if (id == null) return;
    try {
      await _journal.fail(id);
    } on Object {
      /* ignore */
    }
  }

  /// Runs a network op behind the top progress bar, refreshes on success and
  /// toasts the outcome. Errors never escape — they surface as a toast.
  Future<void> _network(String label, Future<void> Function() op) async {
    final toasts = _ref.read(toastProvider.notifier);
    _ref.read(busyProvider.notifier).state = BusyState(label);
    final opId = await _journalBegin(label);
    try {
      await op();
      await _journalDone(opId);
      toasts.show('$label complete', kind: ToastKind.success);
    } on GitException catch (e) {
      await _journalFail(opId);
      // Prefer git's own stderr; fall back to the short message.
      final err = e.result?.err ?? '';
      toasts.show(
        '$label failed',
        description: err.isNotEmpty ? err : e.message,
        kind: ToastKind.error,
      );
    } on Object catch (_) {
      await _journalFail(opId);
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
    final profile = _ref.read(profilesProvider).active;
    // HEAD before the commit — undo soft-resets here, returning the committed
    // changes to the staging area (works for amend too: prev is the original).
    final prev = await _headSha();
    Future<void> doCommit() => _writer.commit(
      summary,
      description: description,
      amend: amend,
      sign: sign,
      coauthors: coauthors,
      authorName: profile?.name,
      authorEmail: profile?.email,
    );
    await _undoable(
      amend ? 'Amend commit' : 'Commit',
      doCommit,
      undo: () => _writer.resetSoft(prev),
      // The changes are staged again after undo, so redo just re-commits.
      redo: doCommit,
    );
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
    final opId = await _journalBegin(label);
    try {
      await run();
      await _journalDone(opId);
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
      await _journalFail(opId);
      _refresh();
      _toastErr(label, e);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Resets to [prev] as part of an undo, but refuses when the working tree is
  /// dirty so an undo never silently discards uncommitted work.
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

  /// Checks out a remote branch: switches to the existing local branch of the
  /// same name, or creates a local tracking branch and switches to it. Undo
  /// returns to the prior branch (deleting the freshly-created local branch).
  Future<void> checkoutRemote(RemoteBranch rb) async {
    if (rb.hasLocal) {
      await checkout(rb.branch);
      return;
    }
    final prev = await _headRef();
    await _undoable(
      'Checkout ${rb.name}',
      () => _writer.checkoutTracking(rb.remote, rb.branch),
      undo: () async {
        await _writer.checkout(prev);
        await _writer.deleteBranch(rb.branch, force: true);
      },
      redo: () => _writer.checkoutTracking(rb.remote, rb.branch),
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

  Future<void> resetHard(String sha) =>
      _resetTo(sha, 'Reset to ${_short(sha)}');

  /// Resets the current branch to a remote-tracking ref (e.g. `origin/x`),
  /// discarding any unpushed commits. Uncommitted work is auto-stashed and the
  /// whole reset is undoable, exactly like [resetHard].
  Future<void> resetToRemote(String ref) => _resetTo(ref, 'Reset to $ref');

  Future<void> _resetTo(String target, String label) async {
    final prev = await _headSha();
    // Tracks the auto-stash created by the current do/redo so undo can pop it
    // back into the working tree — making undo a true inverse of the reset.
    String? stashRef;
    await _undoable(
      label,
      () async {
        stashRef = await _resetPreservingWork(target);
      },
      undo: () async {
        await _undoReset(prev);
        if (stashRef != null) {
          await _writer.stashPop(stashRef!);
          stashRef = null;
        }
      },
      redo: () async {
        stashRef = await _resetPreservingWork(target);
      },
    );
  }

  /// Resets --hard to [sha], first auto-stashing any uncommitted work so it is
  /// never destroyed silently. Returns the created stash ref, or null when the
  /// tree was already clean.
  Future<String?> _resetPreservingWork(String sha) async {
    String? ref;
    if ((await _out(['status', '--porcelain'])).isNotEmpty) {
      await _writer.stashPush(message: 'auto-stash before reset');
      ref = 'stash@{0}';
    }
    await _writer.resetHard(sha);
    return ref;
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

  Future<void> stashPush({String? message, bool stagedOnly = false}) async {
    if (_blockedByNetwork) return;
    try {
      await _writer.stashPush(message: message, stagedOnly: stagedOnly);
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

  // --- Merge ----------------------------------------------------------------

  /// Merges [branch] into the current branch. A clean merge commits and is
  /// undoable; a conflict opens the Merge Tool via [mergeSessionProvider].
  Future<void> merge(String branch) async {
    if (_blockedByNetwork) return;
    final prev = await _headSha();
    _ref.read(busyProvider.notifier).state = BusyState('Merge $branch');
    final id = _identity;
    try {
      await _writer.merge(
        branch,
        noFf: true,
        authorName: id.name,
        authorEmail: id.email,
      );
      _ref
          .read(undoProvider(path).notifier)
          .record(
            UndoEntry(
              'Merge $branch',
              undo: () async {
                await _undoReset(prev);
                _refresh();
              },
              redo: () async {
                await _writer.merge(
                  branch,
                  noFf: true,
                  authorName: id.name,
                  authorEmail: id.email,
                );
                _refresh();
              },
            ),
          );
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show('Merged $branch', kind: ToastKind.success);
    } on GitException catch (e) {
      final conflicts = await GitReader(_git, path).conflictedFiles();
      if (conflicts.isEmpty) {
        _toastErr('Merge', e);
        return;
      }
      final files = [for (final p in conflicts) await _conflictFileFor(p)];
      _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
        branch: branch,
        prevSha: prev,
        files: files,
      );
      _refresh();
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Active-profile identity for new commits, or (null, null) when unset.
  ({String? name, String? email}) get _identity {
    final p = _ref.read(profilesProvider).active;
    return (name: p?.name, email: p?.email);
  }

  /// Switches to [branch] without recording undo (so a drag-drop merge/rebase
  /// is a single undoable action, not checkout+op). Returns false and toasts if
  /// the switch did not land on [branch] (e.g. a dirty tree blocked it).
  Future<bool> _switchTo(String branch) async {
    try {
      await _writer.checkout(branch);
    } on GitException catch (e) {
      _toastErr('Checkout', e);
      return false;
    }
    if (await _headRef() != branch) {
      _ref
          .read(toastProvider.notifier)
          .show('Could not switch to $branch', kind: ToastKind.warning);
      return false;
    }
    return true;
  }

  /// Switches to [target] then merges [source] into it (drag-and-drop). One
  /// undo entry (the merge); the switch is not undoable on its own.
  Future<void> mergeInto(String source, String target) async {
    if (await _switchTo(target)) await merge(source);
  }

  Future<ConflictFile> _conflictFileFor(String rel) async => ConflictFile(
    path: rel,
    parts: parseConflicts(await File('$path/$rel').readAsString()),
  );

  /// Runs an interactive rebase of the plan [steps] onto [base].
  Future<void> rebase(String base, List<RebaseStep> steps) => _runRebase(
    () => _writer.rebase(
      base,
      buildRebaseTodo(steps),
      authorName: _identity.name,
      authorEmail: _identity.email,
    ),
  );

  /// Straight rebase of [source] onto [target] (drag-and-drop rebase).
  Future<void> rebaseOnto(String source, String target) async {
    if (!await _switchTo(source)) return;
    await _runRebase(
      () => _writer.rebaseOnto(
        target,
        authorName: _identity.name,
        authorEmail: _identity.email,
      ),
    );
  }

  /// Commits between [base] and HEAD (oldest-first), as an initial pick plan.
  Future<List<RebaseStep>> rebaseStepsFrom(String base) async {
    final out = await _out([
      'log',
      '--reverse',
      '--format=%H%x1f%s',
      '$base..HEAD',
    ]);
    if (out.isEmpty) return const [];
    return [
      for (final line in out.split('\n'))
        if (line.contains('\x1f'))
          RebaseStep(
            line.split('\x1f')[0],
            RebaseAction.pick,
            message: line.split('\x1f')[1],
          ),
    ];
  }

  Future<void> _runRebase(Future<void> Function() op) async {
    if (_blockedByNetwork) return;
    final prev = await _headSha();
    _ref.read(busyProvider.notifier).state = const BusyState('Rebase');
    try {
      await op();
      _ref
          .read(undoProvider(path).notifier)
          .record(
            UndoEntry(
              'Rebase',
              undo: () async {
                await _undoReset(prev);
                _refresh();
              },
              // Re-run the same rebase op to redo it.
              redo: () async {
                await op();
                _refresh();
              },
            ),
          );
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show('Rebase complete', kind: ToastKind.success);
    } on GitException catch (e) {
      final conflicts = await GitReader(_git, path).conflictedFiles();
      if (conflicts.isEmpty) {
        _toastErr('Rebase', e);
        return;
      }
      _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
        branch: 'rebase',
        prevSha: prev,
        isRebase: true,
        files: [for (final p in conflicts) await _conflictFileFor(p)],
      );
      _refresh();
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Writes the resolved files, stages them, commits the merge, and records an
  /// undo. Call only when the session reports all conflicts resolved.
  Future<void> finishMerge(MergeSession session) async {
    try {
      for (final f in session.files) {
        await File('$path/${f.path}').writeAsString(f.content());
        await _writer.stageFile(f.path);
      }
      final id = _identity;
      if (session.isRebase) {
        await _writer.rebaseContinue(
          authorName: id.name,
          authorEmail: id.email,
        );
        // The rebase may pause again on a later commit; reopen if so.
        final more = await GitReader(_git, path).conflictedFiles();
        if (more.isNotEmpty) {
          _ref.read(mergeSessionProvider(path).notifier).state = session
              .withFiles([for (final p in more) await _conflictFileFor(p)]);
          _refresh();
          return;
        }
      } else {
        await _writer.commitMerge(authorName: id.name, authorEmail: id.email);
      }
      final prev = session.prevSha;
      // The merge/rebase result — redo fast-forwards back to it (it survives in
      // the reflog after undo moves the branch back to prev).
      final after = await _headSha();
      final label = session.isRebase ? 'Rebase' : 'Merge ${session.branch}';
      _ref
          .read(undoProvider(path).notifier)
          .record(
            UndoEntry(
              label,
              undo: () async {
                await _undoReset(prev);
                _refresh();
              },
              redo: () async {
                await _writer.resetHard(after);
                _refresh();
              },
            ),
          );
      _ref.read(mergeSessionProvider(path).notifier).state = null;
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show('$label complete', kind: ToastKind.success);
    } on GitException catch (e) {
      _toastErr('Finish', e);
    }
  }

  Future<void> abortMerge() async {
    final isRebase = _ref.read(mergeSessionProvider(path))?.isRebase ?? false;
    try {
      if (isRebase) {
        await _writer.rebaseAbort();
      } else {
        await _writer.mergeAbort();
      }
    } on GitException catch (e) {
      _toastErr('Abort', e);
    }
    _ref.read(mergeSessionProvider(path).notifier).state = null;
    _refresh();
  }

  static String _short(String sha) =>
      sha.length > 7 ? sha.substring(0, 7) : sha;
}

final repoActionsProvider = Provider.family<RepoActions, String>(
  (ref, path) =>
      RepoActions(ref, path, GitWriter(ref.watch(gitServiceProvider), path)),
);
