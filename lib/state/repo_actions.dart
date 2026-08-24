import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/file_edit.dart';
import '../domain/git/commit_message.dart';
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
import 'workspace.dart';
import 'worktrees.dart';

/// Which shared slot an operation claims while it runs. Fetching gets its own
/// so that the minutes it can take never turn away a commit or a branch
/// create; everything else queues behind the repository slot to stay off git's
/// index and ref locks.
enum _Lane { repo, fetch }

/// Mutating git operations for one repo, each followed by a refresh of
/// [repoDataProvider] so the graph, counts and file lists update in lockstep.
class RepoActions {
  final Ref _ref;
  final String path;
  final GitWriter _writer;
  RepoActions(this._ref, this.path, this._writer);

  void _refresh() => _ref.invalidate(repoDataProvider(path));

  /// Every repo action runs through here so the log records what ran, on
  /// which repo, and how long it took — success and failure alike.
  Future<T> _timed<T>(String label, Future<T> Function() op) =>
      appLog.timed(label, op, scope: path);

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
  Future<void> _network(
    String label,
    Future<void> Function(GitCancel cancel) op, {
    // Background ops (auto-fetch) run silent: no success/failure toast.
    bool silent = false,
    // Fetch and push move objects and refs only. Ops that also write files —
    // pull, submodule update — say so, and an editor save then waits for them.
    bool writesWorkingTree = true,
    _Lane lane = _Lane.repo,
    // Replaces the default '<label> failed' toast title, for an op whose
    // failure leaves the repo in a state the label alone does not describe.
    String? failureTitle,
  }) async {
    final toasts = _ref.read(toastProvider.notifier);
    final slot = lane == _Lane.fetch ? fetchBusyProvider : busyProvider;
    // One op per lane: two ops sharing a lane would race on the busy state
    // (the loser's `finally` clears it mid-flight) and on git's own locks.
    // Background (silent) ops skip quietly instead of warning.
    if (_ref.read(slot) != null) {
      if (!silent) {
        toasts.show('An operation is already running', kind: ToastKind.warning);
      }
      return;
    }
    // Handed to the UI so a stalled remote can be given up on rather than
    // holding the lane until the network timeout expires.
    final cancel = GitCancel();
    _ref.read(slot.notifier).state = writesWorkingTree
        ? BusyState(label, onCancel: cancel.cancel)
        : BusyState.network(label, onCancel: cancel.cancel);
    final opId = await _journalBegin(label);
    try {
      await _timed(label, () => op(cancel));
      await _journalDone(opId);
      if (!silent) toasts.show('$label complete', kind: ToastKind.success);
    } on GitCancelledException {
      await _journalFail(opId);
      if (!silent) {
        toasts.show('$label cancelled', kind: ToastKind.warning);
      }
    } on GitException catch (e) {
      await _journalFail(opId);
      // Prefer git's own stderr; fall back to the short message.
      final err = e.result?.err ?? '';
      if (!silent) {
        toasts.show(
          failureTitle ?? '$label failed',
          description: err.isNotEmpty ? err : e.message,
          kind: ToastKind.error,
        );
      }
    } on Object catch (_) {
      await _journalFail(opId);
      if (!silent) {
        toasts.show(
          failureTitle ?? '$label failed',
          description: 'Unexpected error',
          kind: ToastKind.error,
        );
      }
    } finally {
      // Refresh even on failure: a failed pull/merge can still leave the repo
      // mid-operation (conflicts, MERGING) that the UI must show.
      _refresh();
      _ref.read(slot.notifier).state = null;
    }
  }

  Future<void> fetch({String? remote, bool silent = false}) => _network(
    'Fetch',
    (cancel) => _writer.fetch(remote: remote, cancel: cancel),
    silent: silent,
    writesWorkingTree: false,
    lane: _Lane.fetch,
  );

  /// Shares the fetch lane: pruning rewrites the same remote-tracking refs a
  /// fetch is writing, and nothing else cares about either.
  Future<void> pruneRemote(String remote) => _network(
    'Prune $remote',
    (cancel) => _writer.pruneRemote(remote, cancel: cancel),
    writesWorkingTree: false,
    lane: _Lane.fetch,
  );

  // — Submodules —

  Future<void> submoduleUpdateAll({bool recursive = false}) => _network(
    'Update submodules',
    (_) => _writer.submoduleUpdate(init: true, recursive: recursive),
  );

  Future<void> submoduleUpdate(String path) => _network(
    'Update $path',
    (_) => _writer.submoduleUpdate(path: path, init: true),
  );

  Future<void> submoduleUpdateRemote(String path) => _network(
    'Update $path to remote',
    (_) => _writer.submoduleUpdateRemote(path),
  );

  Future<void> submoduleAdd(String url, String path, {String? branch}) =>
      _network(
        'Add submodule',
        (_) => _writer.submoduleAdd(url, path, branch: branch),
      );

  Future<void> submoduleSync([String? path]) =>
      _network('Sync submodules', (_) => _writer.submoduleSync(path: path));

  Future<void> submoduleDeinit(String path) => _network(
    'Deinit $path',
    (_) => _writer.submoduleDeinit(path, force: true),
  );

  Future<void> submoduleRemove(String path) =>
      _network('Remove $path', (_) => _writer.submoduleRemove(path));

  /// Fetch URL for [remote] (read-only; empty if unset).
  Future<String> remoteUrl(String remote) =>
      GitReader(_git, path).remoteUrl(remote);

  Future<void> addRemote(String name, String url) => _undoable(
    'Add remote $name',
    () => _writer.addRemote(name, url),
    undo: () => _writer.removeRemote(name),
    redo: () => _writer.addRemote(name, url),
  );

  /// Removing a remote also drops its remote-tracking refs; undo restores the
  /// remote's configuration, and a fetch brings the refs back.
  Future<void> removeRemote(String name) async {
    final url = await remoteUrl(name);
    await _undoable(
      'Remove remote $name',
      () => _writer.removeRemote(name),
      undo: () => _writer.addRemote(name, url),
      redo: () => _writer.removeRemote(name),
    );
  }

  /// Applies a new [name] and/or [url] to the remote currently called [from]
  /// as a single undoable step, so an edit touching both is undone as one.
  Future<void> updateRemote(
    String from, {
    required String name,
    required String url,
  }) async {
    final prevUrl = await remoteUrl(from);
    if (name == from && url == prevUrl) return;
    Future<void> forward() async {
      if (name != from) await _writer.renameRemote(from, name);
      if (url != prevUrl) await _writer.setRemoteUrl(name, url);
    }

    Future<void> back() async {
      if (url != prevUrl) await _writer.setRemoteUrl(name, prevUrl);
      if (name != from) await _writer.renameRemote(name, from);
    }

    await _undoable('Edit remote $from', forward, undo: back, redo: forward);
  }

  Future<void> pull({bool rebase = false}) => _network(
    'Pull',
    (cancel) => _writer.pull(rebase: rebase, cancel: cancel),
  );

  Future<void> push({bool force = false}) => _network(
    force ? 'Force push' : 'Push',
    (cancel) => _writer.push(force: force, cancel: cancel),
    writesWorkingTree: false,
  );

  /// True (and toasts) when something already holds the repository lane, so an
  /// index-touching mutation must not run concurrently and race on
  /// `.git/index.lock`. A running fetch is not that: it holds its own lane.
  bool get _blockedByRepoOp {
    if (_ref.read(busyProvider) == null) return false;
    _ref
        .read(toastProvider.notifier)
        .show('An operation is already running', kind: ToastKind.warning);
    return true;
  }

  /// Whether a file write has to wait. Only an operation that rewrites the
  /// working tree conflicts with one; a fetch or a push can run for minutes,
  /// and turning a save away for that long would lose the user's typing.
  bool get _blockedByWorkingTreeOp {
    if (_ref.read(busyProvider)?.touchesWorkingTree != true) return false;
    _ref
        .read(toastProvider.notifier)
        .show('An operation is already running', kind: ToastKind.warning);
    return true;
  }

  Future<void> stageFile(String p) async {
    if (_blockedByRepoOp) return;
    await _timed('Stage $p', () => _writer.stageFile(p));
    _refresh();
  }

  Future<void> unstageFile(String p) async {
    if (_blockedByRepoOp) return;
    await _timed('Unstage $p', () => _writer.unstageFile(p));
    _refresh();
  }

  Future<void> stageAll() async {
    if (_blockedByRepoOp) return;
    await _timed('Stage all', _writer.stageAll);
    _refresh();
  }

  Future<void> unstageAll() async {
    if (_blockedByRepoOp) return;
    await _timed('Unstage all', _writer.unstageAll);
    _refresh();
  }

  Future<void> applyPatch(String patch, {bool reverse = false}) async {
    if (_blockedByRepoOp) return;
    await _timed(
      reverse ? 'Unstage patch' : 'Stage patch',
      () => _writer.applyToIndex(patch, reverse: reverse),
    );
    _refresh();
  }

  /// Discards all uncommitted changes to [f] — a full revert to HEAD for a
  /// tracked file, or deletion for an untracked one. Undoable: undo restores
  /// the working-tree content (and re-stages what was staged).
  Future<void> discardFile(WorkingFile f) async {
    if (_blockedByRepoOp) return;
    final file = File('$path/${f.path}');
    if (f.isUntracked) {
      final bytes = await file.readAsBytes();
      await _undoable(
        'Discard ${f.path}',
        () async => file.delete(),
        undo: () async => file.writeAsBytes(bytes),
        redo: () async => file.delete(),
      );
      return;
    }
    final bytes = await file.readAsBytes();
    final stagedPatch = (await _git.run([
      'diff',
      '--cached',
      '--',
      f.path,
    ], repoPath: path)).stdout;
    Future<void> restore() async {
      await file.writeAsBytes(bytes);
      if (stagedPatch.trim().isNotEmpty) {
        await _writer.applyToIndex(stagedPatch);
      }
    }

    await _undoable(
      'Discard ${f.path}',
      () => _writer.restoreFromHead(f.path),
      undo: restore,
      redo: () => _writer.restoreFromHead(f.path),
    );
  }

  /// Discards every uncommitted change at once: tracked files revert to HEAD,
  /// staged and unstaged alike, and untracked files are deleted when
  /// [includeUntracked] is set. Recorded as one undo entry that puts the
  /// working tree back and re-stages what was staged, so the whole sweep is
  /// reversible in a single step. A clean tree records nothing.
  Future<void> discardAll({bool includeUntracked = false}) async {
    if (_blockedByRepoOp) return;
    final files = await GitReader(_git, path).status();
    final tracked = [
      for (final f in files)
        if (!f.isUntracked) f,
    ];
    final untracked = includeUntracked
        ? [
            for (final f in files)
              if (f.isUntracked) f.path,
          ]
        : const <String>[];
    if (tracked.isEmpty && untracked.isEmpty) return;

    // Every path the sweep can touch, so undo can put the bytes back. A rename
    // moved content away from origPath, which must come back too.
    final paths = <String>{
      for (final f in tracked) ...[f.path, ?f.origPath],
      ...untracked,
    };
    final before = <String, List<int>?>{};
    for (final p in paths) {
      final file = File('$path/$p');
      before[p] = await file.exists() ? await file.readAsBytes() : null;
    }
    final stagedPatch = (await _git.run([
      'diff',
      '--cached',
    ], repoPath: path)).stdout;

    Future<void> discard() async {
      if (tracked.isNotEmpty) await _writer.restoreAllFromHead();
      for (final p in untracked) {
        final file = File('$path/$p');
        if (await file.exists()) await file.delete();
      }
    }

    Future<void> restore() async {
      for (final entry in before.entries) {
        final file = File('$path/${entry.key}');
        if (entry.value == null) {
          if (await file.exists()) await file.delete();
        } else {
          await file.parent.create(recursive: true);
          await file.writeAsBytes(entry.value!);
        }
      }
      if (stagedPatch.trim().isNotEmpty) {
        await _writer.applyToIndex(stagedPatch);
      }
    }

    await _undoable(
      'Discard all changes',
      discard,
      undo: restore,
      redo: discard,
    );
  }

  /// Reverts a single hunk in the working tree ([patch] is a stage-style hunk
  /// patch); undoable.
  Future<void> discardHunk(String patch) async {
    if (_blockedByRepoOp) return;
    await _undoable(
      'Discard hunk',
      () => _writer.applyToWorktree(patch, reverse: true),
      undo: () => _writer.applyToWorktree(patch),
      redo: () => _writer.applyToWorktree(patch, reverse: true),
    );
  }

  /// Writes [text] to the working-tree file at [relPath], creating it when it
  /// is missing. Undo puts back exactly the bytes that were there before, or
  /// removes the file again when it was newly created. The result is left
  /// unstaged — staging stays a separate, explicit step.
  ///
  /// Returns whether the file was written. Callers must not discard the text
  /// they passed in until this reports true: a save can be refused because
  /// another operation holds the repo, or fail on the filesystem.
  Future<bool> saveFileText(String relPath, String text) async {
    if (_blockedByWorkingTreeOp) return false;
    // Only plain repo-relative paths are ever offered for editing; anything
    // else could address a file outside the repository.
    if (!isRepoRelativePath(relPath)) return false;
    final file = File('$path/$relPath');
    // Reject writes through symlinks that escape the repository.
    if (file.existsSync() && !isInsideRepo(path, file.path)) return false;
    Future<void> write() => file.writeAsString(text);
    var saved = false;
    try {
      final before = await file.exists() ? await file.readAsBytes() : null;
      await _undoable(
        'Edit $relPath',
        () async {
          await write();
          saved = true;
        },
        undo: () async {
          if (before != null) {
            await file.writeAsBytes(before);
          } else if (await file.exists()) {
            await file.delete();
          }
        },
        redo: write,
        // Writing one file races with nothing git holds a lock for, and the
        // op it may be running alongside owns the busy flag.
        claimsRepo: false,
      );
    } on FileSystemException catch (e) {
      // _undoable only converts GitException into a toast; a failed write
      // would otherwise escape as an unhandled async error.
      _ref
          .read(toastProvider.notifier)
          .show(
            'Could not save $relPath',
            description: e.osError?.message ?? e.message,
            kind: ToastKind.error,
          );
      return false;
    }
    return saved;
  }

  Future<void> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    List<String> coauthors = const [],
  }) async {
    if (_blockedByRepoOp) return;
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
    // Set false by an op that writes a working-tree file and nothing else: it
    // needs no lock of its own and must not take the one a running op holds.
    bool claimsRepo = true,
  }) async {
    if (claimsRepo) {
      if (_blockedByRepoOp) return;
      // Hold the shared busy flag so a second ref op (or network op) cannot
      // run concurrently and race on .git/index.lock.
      _ref.read(busyProvider.notifier).state = BusyState(label);
    }
    final opId = await _journalBegin(label);
    try {
      await _timed(label, run);
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
      // Clearing a flag this op never set would let the op that does own it
      // disappear from the progress bar mid-run.
      if (claimsRepo) _ref.read(busyProvider.notifier).state = null;
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
    if (_blockedByRepoOp) return;
    _ref.read(busyProvider.notifier).state = const BusyState('Undo');
    try {
      await _timed('Undo', _ref.read(undoProvider(path).notifier).undo);
    } on GitException catch (e) {
      _toastErr('Undo', e);
    } on Object catch (e) {
      // File-edit undo entries do filesystem writes, which can fail with
      // more than GitException; surface it rather than crash.
      _ref
          .read(toastProvider.notifier)
          .show('Undo failed', description: '$e', kind: ToastKind.error);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  Future<void> redo() async {
    if (_blockedByRepoOp) return;
    _ref.read(busyProvider.notifier).state = const BusyState('Redo');
    try {
      await _timed('Redo', _ref.read(undoProvider(path).notifier).redo);
    } on GitException catch (e) {
      _toastErr('Redo', e);
    } on Object catch (e) {
      _ref
          .read(toastProvider.notifier)
          .show('Redo failed', description: '$e', kind: ToastKind.error);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  Future<void> checkout(String ref, {bool ignoreOtherWorktrees = false}) async {
    final prev = await _headRef();
    await _undoable(
      'Checkout $ref',
      () => _writer.checkout(ref, ignoreOtherWorktrees: ignoreOtherWorktrees),
      undo: () => _writer.checkout(prev),
      redo: () =>
          _writer.checkout(ref, ignoreOtherWorktrees: ignoreOtherWorktrees),
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

  /// Switches to the local branch [rb.branch] and hard-resets it to the remote
  /// [rb.name], auto-stashing any uncommitted work first. One undoable action:
  /// undo restores the local branch's prior sha, returns to the prior branch,
  /// and pops the auto-stash. [ignoreOtherWorktrees] passes
  /// `--ignore-other-worktrees` on the initial checkout (and on redo), for
  /// callers that already confirmed overriding a worktree collision; undo
  /// never needs it since by then this repo already holds the branch.
  Future<void> switchResettingToRemote(
    RemoteBranch rb, {
    bool ignoreOtherWorktrees = false,
  }) async {
    final prevBranch = await _headRef();
    final prevLocalSha = await _out(['rev-parse', rb.branch]);
    String? stashRef;
    await _undoable(
      'Reset ${rb.branch} to ${rb.name}',
      () async {
        stashRef = await _switchAndResetToRemote(
          rb,
          ignoreOtherWorktrees: ignoreOtherWorktrees,
        );
      },
      undo: () async {
        await _writer.checkout(rb.branch);
        await _writer.resetHard(prevLocalSha);
        await _writer.checkout(prevBranch);
        if (stashRef != null) {
          await _writer.stashPop(stashRef!);
          stashRef = null;
        }
      },
      redo: () async {
        stashRef = await _switchAndResetToRemote(
          rb,
          ignoreOtherWorktrees: ignoreOtherWorktrees,
        );
      },
    );
  }

  /// Stashes dirty work (if any), checks out [rb.branch], resets it hard to the
  /// remote ref. Returns the created stash ref, or null when the tree was clean.
  Future<String?> _switchAndResetToRemote(
    RemoteBranch rb, {
    bool ignoreOtherWorktrees = false,
  }) async {
    String? ref;
    if ((await _out(['status', '--porcelain'])).isNotEmpty) {
      await _writer.stashPush(message: 'auto-stash before switch');
      ref = 'stash@{0}';
    }
    await _writer.checkout(
      rb.branch,
      ignoreOtherWorktrees: ignoreOtherWorktrees,
    );
    await _writer.resetHard('${rb.remote}/${rb.branch}');
    return ref;
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

  /// Deletes the branch behind [rb] on its remote. No undo entry: re-pushing
  /// the old sha would resurrect a ref that someone else may have moved on
  /// since, which is not the same thing as putting it back.
  Future<void> deleteRemoteBranch(RemoteBranch rb) => _network(
    'Delete ${rb.name}',
    (cancel) =>
        _writer.deleteRemoteBranch(rb.remote, rb.branch, cancel: cancel),
    writesWorkingTree: false,
  );

  /// Deletes [name] here and then on the remote behind [upstream] (`origin/x`).
  /// Two git commands, so the local ref can go while the push fails — the
  /// failure then names what is left behind rather than implying nothing
  /// happened. Only the local half lands on the undo stack.
  Future<void> deleteBranchAndRemote(String name, String upstream) async {
    final slash = upstream.indexOf('/');
    if (slash <= 0) return;
    await deleteBranch(name);
    // deleteBranch reports its own failure. Stop when the ref survived, so a
    // refused local delete does not still wipe the branch on the remote.
    if (await _branchExists(name)) return;
    await _network(
      'Delete $upstream',
      (cancel) => _writer.deleteRemoteBranch(
        upstream.substring(0, slash),
        upstream.substring(slash + 1),
        cancel: cancel,
      ),
      writesWorkingTree: false,
      failureTitle: 'Deleted $name here — $upstream is still on the remote',
    );
  }

  Future<bool> _branchExists(String name) async => (await _git.run([
    'rev-parse',
    '--verify',
    '--quiet',
    'refs/heads/$name',
  ], repoPath: path)).ok;

  Future<void> renameBranch(String from, String to) => _undoable(
    'Rename $from → $to',
    () => _writer.renameBranch(from, to),
    undo: () => _writer.renameBranch(to, from),
    redo: () => _writer.renameBranch(from, to),
  );

  Future<void> setUpstream(String branch, String upstream) async {
    if (_blockedByRepoOp) return;
    try {
      await _timed(
        'Set upstream $branch → $upstream',
        () => _writer.setUpstream(branch, upstream),
      );
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
    if (_blockedByRepoOp) return;
    try {
      await _timed('Push tag $name', () => _writer.pushTag(name));
      _ref
          .read(toastProvider.notifier)
          .show('Pushed tag $name', kind: ToastKind.success);
    } on GitException catch (e) {
      _toastErr('Push tag', e);
    }
  }

  Future<void> stashPush({String? message, bool stagedOnly = false}) async {
    if (_blockedByRepoOp) return;
    try {
      await _timed(
        'Stash push',
        () => _writer.stashPush(message: message, stagedOnly: stagedOnly),
      );
      _refresh();
    } on GitException catch (e) {
      _toastErr('Stash', e);
    }
  }

  Future<void> stashApply(String ref) async {
    if (_blockedByRepoOp) return;
    try {
      await _timed('Stash apply $ref', () => _writer.stashApply(ref));
      _refresh();
    } on GitException catch (e) {
      await _openStashConflictOrToast('Stash apply', e, dropRef: null);
    }
  }

  Future<void> stashPop(String ref) async {
    if (_blockedByRepoOp) return;
    try {
      await _timed('Stash pop $ref', () => _writer.stashPop(ref));
      _refresh();
    } on GitException catch (e) {
      // A conflicted pop keeps the stash; drop it once the resolution finishes.
      await _openStashConflictOrToast('Stash pop', e, dropRef: ref);
    }
  }

  /// After a failed stash apply/pop, open a resolution session when the failure
  /// left conflicts in the tree; otherwise surface the error toast.
  Future<void> _openStashConflictOrToast(
    String label,
    GitException e, {
    required String? dropRef,
  }) async {
    final conflicts = await GitReader(_git, path).conflictedFiles();
    if (conflicts.isEmpty) {
      _toastErr(label, e);
      return;
    }
    _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
      kind: MergeKind.stash,
      branch: 'Stashed changes',
      dropStashRef: dropRef,
      files: [for (final p in conflicts) await _conflictFileFor(p)],
    );
    _refresh();
  }

  /// Drops a stash, offering an Undo toast that re-stores it (drop is not part
  /// of the ref undo stack because the stash index shifts).
  Future<void> stashDrop(String ref) async {
    if (_blockedByRepoOp) return;
    try {
      final sha = await _timed('Stash drop $ref', () => _writer.stashDrop(ref));
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
    if (_blockedByRepoOp) return;
    final prev = await _headSha();
    _ref.read(busyProvider.notifier).state = BusyState('Merge $branch');
    final id = _identity;
    try {
      await _timed(
        'Merge $branch',
        () => _writer.merge(
          branch,
          noFf: true,
          authorName: id.name,
          authorEmail: id.email,
        ),
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
        kind: MergeKind.merge,
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

  /// Merges [source] into the branch behind the remote-tracking ref [rb]. A
  /// remote-tracking ref cannot carry a merge commit, so the work lands on its
  /// local counterpart. Like [mergeInto], this is one undo entry (the merge);
  /// the switch is not undoable on its own.
  Future<void> mergeIntoRemote(String source, RemoteBranch rb) async {
    if (await _switchToRemote(rb)) await merge(source);
  }

  /// Puts HEAD on the local branch behind [rb], creating it as a tracking
  /// branch when there is none. [RemoteBranch.hasLocal] only reflects the last
  /// repository read, so a failed create falls back to a plain switch rather
  /// than reporting an error for a branch that does exist.
  Future<bool> _switchToRemote(RemoteBranch rb) async {
    if (rb.hasLocal) return _switchTo(rb.branch);
    try {
      await _writer.checkoutTracking(rb.remote, rb.branch);
    } on GitException {
      return _switchTo(rb.branch);
    }
    if (await _headRef() != rb.branch) {
      _ref
          .read(toastProvider.notifier)
          .show('Could not switch to ${rb.branch}', kind: ToastKind.warning);
      return false;
    }
    return true;
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

  /// True while the repository sits mid-rebase. Asks git for the path rather
  /// than assuming `.git/rebase-merge`, which is wrong inside a linked
  /// worktree, where the state lives under `.git/worktrees/<name>/`.
  Future<bool> isRebaseInProgress() async {
    for (final dir in const ['rebase-merge', 'rebase-apply']) {
      final p = (await _out(['rev-parse', '--git-path', dir])).trim();
      if (p.isEmpty) continue;
      final abs = p.startsWith('/') ? p : '$path/$p';
      if (Directory(abs).existsSync()) return true;
    }
    return false;
  }

  /// True when running [plan] would leave history exactly as it is: the plan
  /// still picks every commit in its original order, *and* [base] is a commit
  /// HEAD already contains, so replaying onto it lands where we started. An
  /// unchanged pick list onto a base off this branch is not redundant — moving
  /// the commits there is the whole point.
  Future<bool> isRebaseRedundant(
    String base,
    List<RebaseStep> original,
    List<RebaseStep> plan,
  ) async {
    if (!isNoOpPlan(original, plan)) return false;
    return _isAncestorOfHead(base);
  }

  /// Whether replaying [base]..HEAD would have to replay a merge commit. An
  /// empty [base] means the root, and so the whole history.
  ///
  /// A linear plan of picks cannot express a merge, and git refuses a todo
  /// that names one — mid-rebase, leaving HEAD detached on the base with no
  /// conflict for the UI to offer a way out of. Callers refuse before starting.
  Future<bool> rebaseCrossesMerge(String base) async => (await _out([
    'rev-list',
    '--merges',
    base.isEmpty ? 'HEAD' : '$base..HEAD',
  ])).isNotEmpty;

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

  /// Remote-tracking branches that already contain [sha]. Empty means the
  /// commit has never left this machine, so rewriting it costs nobody a force
  /// push; the caller warns when it is not.
  Future<List<String>> remoteBranchesContaining(String sha) async {
    final out = await _out([
      'branch',
      '-r',
      '--contains',
      sha,
      '--format=%(refname:short)',
    ]);
    return [
      for (final line in out.split('\n'))
        if (line.trim().isNotEmpty && !line.trim().endsWith('/HEAD'))
          line.trim(),
    ];
  }

  /// Rewrites the message of [sha], leaving its tree untouched. HEAD is amended
  /// in place; an older commit is reworded through an interactive rebase, which
  /// necessarily rewrites every commit above it. A commit that is not an
  /// ancestor of HEAD cannot be reached either way, so it is refused rather
  /// than silently rebasing the wrong branch.
  Future<void> rewordCommit(
    String sha,
    String summary, {
    String description = '',
  }) async {
    final toasts = _ref.read(toastProvider.notifier);
    if (summary.trim().isEmpty) {
      toasts.show('Commit message is empty', kind: ToastKind.warning);
      return;
    }
    final target = await _out(['rev-parse', sha]);
    // 'N' is the only status meaning "no signature at all"; every other one
    // (including 'E', key missing locally) describes a commit that was signed,
    // and rewriting it unsigned would quietly downgrade it.
    final wasSigned =
        (await _out(['log', '-1', '--format=%G?', target])) != 'N';
    if (target == await _headSha()) {
      if (_blockedByRepoOp) return;
      final prev = target;
      Future<void> amend() => _writer.amendMessage(
        summary,
        description: description,
        sign: wasSigned,
        authorName: _identity.name,
        authorEmail: _identity.email,
      );
      // The tree is unchanged, so soft-resetting to the original commit puts
      // history back exactly as it was and stages nothing extra.
      await _undoable(
        'Reword commit',
        amend,
        undo: () => _writer.resetSoft(prev),
        redo: amend,
      );
      return;
    }
    if (!await _isAncestorOfHead(target)) {
      toasts.show(
        'Commit is not on the current branch',
        kind: ToastKind.warning,
      );
      return;
    }
    // An empty parent means the root commit, which git rebases with `--root`.
    final parent = await _out(['rev-parse', '--verify', '--quiet', '$target^']);
    final range = parent.isEmpty ? 'HEAD' : '$parent..HEAD';
    if (await rebaseCrossesMerge(parent)) {
      toasts.show(
        'Cannot edit this message',
        description:
            'Rewriting it would replay a merge commit, which would flatten '
            'the history above it.',
        kind: ToastKind.warning,
      );
      return;
    }
    final log = await _out(['log', '--reverse', '--format=%H', range]);
    final message = joinCommitMessage(summary, description);
    final steps = [
      for (final line in log.split('\n'))
        if (line.trim().isNotEmpty)
          if (line.trim() == target)
            RebaseStep(
              line.trim(),
              RebaseAction.reword,
              message: message,
              sign: wasSigned,
            )
          else
            RebaseStep(line.trim(), RebaseAction.pick),
    ];
    if (steps.isEmpty) return;
    await rebase(parent.isEmpty ? '--root' : parent, steps);
  }

  Future<bool> _isAncestorOfHead(String sha) async => (await _git.run([
    'merge-base',
    '--is-ancestor',
    sha,
    'HEAD',
  ], repoPath: path)).ok;

  Future<void> _runRebase(Future<void> Function() op) async {
    if (_blockedByRepoOp) return;
    if (await isRebaseInProgress()) {
      _ref
          .read(toastProvider.notifier)
          .show(
            'A rebase is already in progress',
            description: 'Finish or abort it before starting another one.',
            kind: ToastKind.warning,
            action: ToastAction('Abort rebase', () async {
              try {
                await _writer.rebaseAbort();
                _refresh();
              } on GitException catch (e) {
                _toastErr('Abort rebase', e);
              }
            }),
          );
      return;
    }
    final prev = await _headSha();
    _ref.read(busyProvider.notifier).state = const BusyState('Rebase');
    try {
      await _timed('Rebase', op);
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
        // Nothing to resolve, so there is no session to hand the user. git may
        // still have left the repository mid-rebase (a todo it refused, a
        // failed exec); roll that back rather than stranding the repository in
        // a state only a terminal can escape.
        if (await isRebaseInProgress()) await _writer.rebaseAbort();
        _toastErr('Rebase', e);
        return;
      }
      _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
        branch: 'rebase',
        prevSha: prev,
        kind: MergeKind.rebase,
        files: [for (final p in conflicts) await _conflictFileFor(p)],
      );
      _refresh();
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Writes the resolved files and stages them, then completes the session by
  /// its kind: a merge commits, a rebase continues, a stash just stages (and
  /// drops its stash). Call only when the session reports all conflicts
  /// resolved.
  Future<void> finishMerge(MergeSession session) async {
    final label = switch (session.kind) {
      MergeKind.rebase => 'Finish rebase',
      MergeKind.merge => 'Finish merge ${session.branch}',
      MergeKind.stash => 'Finish conflict resolution',
    };
    try {
      await _timed(label, () => _finishMerge(session));
    } on GitException catch (e) {
      _toastErr('Finish', e);
    }
  }

  Future<void> _finishMerge(MergeSession session) async {
    for (final f in session.files) {
      await File('$path/${f.path}').writeAsString(f.content());
      await _writer.stageFile(f.path);
    }
    final id = _identity;
    switch (session.kind) {
      case MergeKind.rebase:
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
        await _recordFinishUndo(session, 'Rebase');
      case MergeKind.merge:
        await _writer.commitMerge(authorName: id.name, authorEmail: id.email);
        await _recordFinishUndo(session, 'Merge ${session.branch}');
      case MergeKind.stash:
        // Stage-only: no commit. A conflicted pop kept its stash — drop it.
        if (session.dropStashRef != null) {
          await _writer.stashDrop(session.dropStashRef!);
        }
    }
    _ref.read(mergeSessionProvider(path).notifier).state = null;
    _refresh();
    final done = switch (session.kind) {
      MergeKind.rebase => 'Rebase complete',
      MergeKind.merge => 'Merge ${session.branch} complete',
      MergeKind.stash => 'Conflicts resolved',
    };
    _ref.read(toastProvider.notifier).show(done, kind: ToastKind.success);
  }

  /// Records the undo/redo entry for a completed merge/rebase: undo resets the
  /// branch back to [session.prevSha]; redo fast-forwards to the finished
  /// result (which survives in the reflog).
  Future<void> _recordFinishUndo(MergeSession session, String label) async {
    final prev = session.prevSha;
    final after = await _headSha();
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
  }

  /// Opens a conflict-resolution session for any conflicted files already in
  /// the working tree (e.g. a conflicted stash apply). No-op when a session is
  /// active or nothing is conflicted; the finish stages the resolution only.
  Future<void> openConflictResolution() async {
    if (_ref.read(mergeSessionProvider(path)) != null) return;
    final conflicts = await GitReader(_git, path).conflictedFiles();
    if (conflicts.isEmpty) return;
    _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
      kind: MergeKind.stash,
      branch: '',
      files: [for (final p in conflicts) await _conflictFileFor(p)],
    );
  }

  Future<void> abortMerge() async {
    final kind = _ref.read(mergeSessionProvider(path))?.kind ?? MergeKind.merge;
    try {
      await _timed('Abort ${kind.name}', () async {
        switch (kind) {
          case MergeKind.rebase:
            await _writer.rebaseAbort();
          case MergeKind.merge:
            await _writer.mergeAbort();
          case MergeKind.stash:
            // No in-progress merge to abort; discard the conflicted apply. A
            // stash-sourced conflict keeps its stash, so the work is
            // recoverable.
            await _writer.resetHard('HEAD');
        }
      });
    } on GitException catch (e) {
      _toastErr('Abort', e);
    }
    _ref.read(mergeSessionProvider(path).notifier).state = null;
    _refresh();
  }

  static String _short(String sha) =>
      sha.length > 7 ? sha.substring(0, 7) : sha;

  /// A local (non-network) mutation: time it, toast the outcome, refresh.
  ///
  /// Unlike [_network] it writes no journal entry and registers no undo step —
  /// worktree operations create and delete directories, which no git command
  /// puts back.
  Future<bool> _local(String label, Future<void> Function() op) async {
    try {
      await _timed(label, op);
      _ref
          .read(toastProvider.notifier)
          .show('$label complete', kind: ToastKind.success);
      return true;
    } on GitException catch (e) {
      _toastErr(label, e);
      return false;
    } on Object catch (_) {
      _ref
          .read(toastProvider.notifier)
          .show(
            '$label failed',
            description: 'Unexpected error',
            kind: ToastKind.error,
          );
      return false;
    } finally {
      _refresh();
      _invalidateWorktrees();
    }
  }

  /// Every open tab shows the same worktree list, so a mutation made from one
  /// of them invalidates the whole family rather than this repository's entry:
  /// a sibling tab must not keep serving a cached list that still contains a
  /// worktree this call just removed. Passing the family itself invalidates
  /// every instance of it.
  void _invalidateWorktrees() => _ref.invalidate(worktreesProvider);

  Future<bool> worktreeAdd(
    String at, {
    String? newBranch,
    String? startPoint,
    String? existingBranch,
    bool detach = false,
  }) => _local(
    'Add worktree',
    () => _writer.addWorktree(
      at,
      newBranch: newBranch,
      startPoint: startPoint,
      existingBranch: existingBranch,
      detach: detach,
    ),
  );

  /// Removes the worktree at [at], closing any tab that showed it.
  ///
  /// Returns null on success, or git's own message when it refused — the
  /// caller turns that into the force-escalation prompt, so no toast is shown
  /// for the refusal.
  Future<String?> worktreeRemove(String at, {bool force = false}) async {
    try {
      await _timed(
        'Remove worktree',
        () => _writer.removeWorktree(at, force: force),
      );
      _ref.read(workspaceProvider.notifier).closeTabsAt(at);
      _ref
          .read(toastProvider.notifier)
          .show('Remove worktree complete', kind: ToastKind.success);
      return null;
    } on GitException catch (e) {
      final err = e.result?.err ?? '';
      return err.isNotEmpty ? err : e.message;
    } on Object catch (_) {
      return 'Unexpected error';
    } finally {
      _refresh();
      _invalidateWorktrees();
    }
  }

  /// Moves the worktree at [from] to [to], taking any tab showing it along —
  /// the checkout is the same one, only its directory changed, and a tab left
  /// on the old path would sit on nothing.
  Future<bool> worktreeMove(String from, String to) async {
    final ok = await _local(
      'Move worktree',
      () => _writer.moveWorktree(from, to),
    );
    if (ok) _ref.read(workspaceProvider.notifier).retargetTabs(from, to);
    return ok;
  }

  Future<bool> worktreeLock(String at, {String? reason}) =>
      _local('Lock worktree', () => _writer.lockWorktree(at, reason: reason));

  Future<bool> worktreeUnlock(String at) =>
      _local('Unlock worktree', () => _writer.unlockWorktree(at));

  /// Returns git's report. A dry run changes nothing and is shown to the user
  /// before the real prune.
  Future<String> worktreePrune({bool dryRun = false}) async {
    try {
      return await _timed(
        dryRun ? 'Preview prune' : 'Prune worktrees',
        () => _writer.pruneWorktrees(dryRun: dryRun),
      );
    } on GitException catch (e) {
      _toastErr('Prune worktrees', e);
      return '';
    } on Object catch (_) {
      _ref
          .read(toastProvider.notifier)
          .show(
            'Prune worktrees failed',
            description: 'Unexpected error',
            kind: ToastKind.error,
          );
      return '';
    } finally {
      if (!dryRun) {
        _refresh();
        _invalidateWorktrees();
      }
    }
  }
}

final repoActionsProvider = Provider.family<RepoActions, String>(
  (ref, path) =>
      RepoActions(ref, path, GitWriter(ref.watch(gitServiceProvider), path)),
);
