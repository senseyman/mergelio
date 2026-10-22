import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/concurrency.dart';
import '../core/logging.dart';
import '../domain/external_tools.dart';
import '../domain/file_edit.dart';
import '../domain/git/bisect.dart';
import '../domain/git/commit_message.dart';
import '../domain/git/conflict.dart';
import '../domain/git/external_git_tools.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/git_service.dart';
import '../domain/git/git_writer.dart';
import '../domain/git/hooks.dart';
import '../domain/git/in_flight_git.dart';
import '../domain/git/ignore.dart';
import '../domain/git/lfs.dart';
import '../domain/git/maintenance.dart';
import '../domain/git/models.dart';
import '../domain/git/notes.dart';
import '../domain/git/patch_file.dart';
import '../domain/git/rebase_plan.dart';
import '../domain/git/stash.dart';
import '../l10n/gen/app_localizations.dart';
import 'bisect.dart';
import 'diff_target.dart';
import 'external_tools.dart';
import 'feedback.dart';
import 'forge_refresh.dart';
import 'merge_session.dart';
import 'operation_journal.dart';
import 'profiles.dart';
import 'graph_selection.dart';
import 'l10n.dart';
import 'lfs.dart';
import 'repo_data.dart';
import 'settings_controller.dart';
import 'undo_stack.dart';
import 'workspace.dart';
import 'worktrees.dart';

/// Which shared slot an operation claims while it runs. Fetching gets its own
/// so that the minutes it can take never turn away a commit or a branch
/// create; everything else queues behind the repository slot to stay off git's
/// index and ref locks.
enum _Lane { repo, fetch }

/// How long operations have to stop arriving before the graph reloads.
///
/// Well under what a reload itself costs, so the graph still looks like it
/// updated with the click, but long enough to cover the gap between the two
/// operations one gesture can be — creating a branch and checking it out are
/// milliseconds apart, and reloading after each reads the whole repository
/// twice. The watcher settles for far longer because disk events arrive in
/// storms; these are deliberate acts, and there are never many in a row.
const actionSettle = Duration(milliseconds: 80);

/// Mutating git operations for one repo, each followed by a refresh of
/// [repoDataProvider] so the graph, counts and file lists update in lockstep.
class RepoActions {
  final Ref _ref;
  final String path;
  final GitWriter _writer;
  late final RefreshCoalescer _refreshes;

  /// Every git command the actions run, counted while it runs. [_writer] is
  /// given the same one by [repoActionsProvider]; one built elsewhere keeps
  /// its own, and only the reads made here are counted.
  final InFlightGit? _tracked;

  RepoActions(this._ref, this.path, this._writer, {InFlightGit? git})
    : _tracked = git {
    _refreshes = RefreshCoalescer(
      settle: actionSettle,
      busy: () => _ref.read(repoDataProvider(path)).isLoading,
      // An action between two of its commands is not done: the reload its
      // first step asked for would only be read again after its last.
      held: () => (_tracked?.inFlight ?? 0) > 0,
      onRefresh: () => _ref.invalidate(repoDataProvider(path)),
    );
  }

  /// One gesture can be several operations — creating a branch and checking it
  /// out, or resolving conflicts and staging — and each one lands here. Asking
  /// for the reload rather than starting it lets a run of them share a single
  /// read of the repository instead of racing each other through one.
  void _refresh() => _refreshes.schedule();

  /// Schedules the same coalesced reload for a change made to this repository
  /// from outside it — a fetch or pull the dashboard ran across a group.
  void refresh() => _refresh();

  /// Drops a reload that has not run yet. The provider disposes this.
  void dispose() => _refreshes.cancel();

  /// Read per message rather than held, so a language switch applies to the
  /// next toast without rebuilding the actions.
  AppLocalizations get _l => _ref.read(appL10nProvider);

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
  /// toasts the outcome. Errors never escape — they surface as a toast, and as
  /// a false return for callers (auto-fetch) that pace themselves on failure.
  /// A skip, because the lane is busy, counts as no failure.
  Future<bool> _network(
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
    // Runs only when [op] actually completed — never on a busy-lane skip or
    // a cancellation, both of which return true above without anything
    // having happened.
    void Function()? onSuccess,
    // An op whose result the caller shows itself (a preview) wants failures
    // toasted but not its own success.
    bool toastSuccess = true,
  }) async {
    final toasts = _ref.read(toastProvider.notifier);
    final slot = lane == _Lane.fetch ? fetchBusyProvider : busyProvider;
    // One op per lane: two ops sharing a lane would race on the busy state
    // (the loser's `finally` clears it mid-flight) and on git's own locks.
    // Background (silent) ops skip quietly instead of warning.
    if (_ref.read(slot) != null) {
      if (!silent) {
        toasts.show(_l.actBusy, kind: ToastKind.warning);
      }
      return true;
    }
    // Handed to the UI so a stalled remote can be given up on rather than
    // holding the lane until the network timeout expires.
    final cancel = GitCancel();
    _ref.read(slot.notifier).state = writesWorkingTree
        ? BusyState(label, onCancel: cancel.cancel)
        : BusyState.network(label, onCancel: cancel.cancel);
    final opId = await _journalBegin(label);
    try {
      // A network op waits on the remote: holding the view's refresh for it
      // would only make other actions' changes show late.
      await _timed(label, () => InFlightGit.uncounted(() => op(cancel)));
      await _journalDone(opId);
      onSuccess?.call();
      if (!silent && toastSuccess) {
        toasts.show(_l.actComplete(label), kind: ToastKind.success);
      }
      return true;
    } on GitCancelledException {
      await _journalFail(opId);
      if (!silent) {
        toasts.show(_l.actCancelled(label), kind: ToastKind.warning);
      }
      // Giving up on purpose is not the remote failing.
      return true;
    } on GitException catch (e) {
      await _journalFail(opId);
      // Prefer git's own stderr; fall back to the short message.
      final err = e.result?.err ?? '';
      if (!silent) {
        toasts.show(
          failureTitle ?? _l.actFailed(label),
          description: err.isNotEmpty ? err : e.message,
          kind: ToastKind.error,
        );
      }
      return false;
    } on Object catch (_) {
      await _journalFail(opId);
      if (!silent) {
        toasts.show(
          failureTitle ?? _l.actFailed(label),
          description: _l.actUnexpectedError,
          kind: ToastKind.error,
        );
      }
      return false;
    } finally {
      // Refresh even on failure: a failed pull/merge can still leave the repo
      // mid-operation (conflicts, MERGING) that the UI must show.
      _refresh();
      _ref.read(slot.notifier).state = null;
    }
  }

  Future<bool> fetch({String? remote, bool silent = false}) => _network(
    _l.actFetch,
    (cancel) => _writer.fetch(remote: remote, cancel: cancel),
    silent: silent,
    writesWorkingTree: false,
    lane: _Lane.fetch,
    // Only a fetch the user asked for earns a forge refresh. Auto-fetch's
    // silent background polling ticks every few minutes and must not spend
    // the same rate-limit budget again each time it runs.
    onSuccess: silent
        ? null
        : () {
            _ref.read(forgeRefreshProvider).refreshAfterGitOp(path);
            _bumpLfs();
          },
  );

  /// Downloads the history a shallow clone left out, and the branches a
  /// single-branch one did. On the fetch lane: like a fetch it writes objects
  /// and refs, never the working tree.
  ///
  /// Widening a single-branch remote rewrites its fetch refspec in the repo
  /// config for good (`remote set-branches <remote> '*'`), so later fetches
  /// keep bringing every branch. A blobless clone stays blobless: file
  /// contents still arrive on demand.
  ///
  /// A repository that is already complete has nothing to fetch, and git
  /// refuses `--unshallow` on one, so it is left as it is.
  Future<bool> fetchFullHistory() => _network(
    _l.actFetchFullHistory,
    (cancel) async {
      final reader = GitReader(_git, path);
      if (!await reader.isShallow()) return;
      for (final remote in await reader.singleBranchRemotes()) {
        await _writer.fetchAllBranches(remote);
      }
      await _writer.unshallow(cancel: cancel);
    },
    writesWorkingTree: false,
    lane: _Lane.fetch,
  );

  /// Shares the fetch lane: pruning rewrites the same remote-tracking refs a
  /// fetch is writing, and nothing else cares about either.
  Future<void> pruneRemote(String remote) => _network(
    _l.actPruneRemote(remote),
    (cancel) => _writer.pruneRemote(remote, cancel: cancel),
    writesWorkingTree: false,
    lane: _Lane.fetch,
  );

  // — Git LFS —

  /// LFS state git status cannot see changes after every LFS operation; the
  /// providers that show it follow this counter.
  void _bumpLfs() => _ref.read(lfsGenerationProvider(path).notifier).state++;

  Future<bool> _lfsNetwork(
    String label,
    Future<void> Function(GitCancel cancel) op, {
    _Lane lane = _Lane.repo,
    bool writesWorkingTree = true,
    bool toastSuccess = true,
  }) async {
    try {
      return await _network(
        label,
        (c) async {
          try {
            await op(c);
          } on GitException catch (e) {
            // git-lfs's own wording names an empty URL; say what it means.
            if (!lfsNoRemote(e.result?.err ?? '')) rethrow;
            throw GitException(_l.actLfsNoRemote);
          }
        },
        lane: lane,
        writesWorkingTree: writesWorkingTree,
        toastSuccess: toastSuccess,
      );
    } finally {
      _bumpLfs();
    }
  }

  Future<bool> _lfsLocal(String label, Future<void> Function() op) async {
    if (_blockedByRepoOp) return false;
    try {
      return await _local(label, op);
    } finally {
      _bumpLfs();
    }
  }

  /// Downloads LFS content and replaces working-tree pointers with it.
  Future<void> lfsPull() =>
      _lfsNetwork(_l.actLfsPull, (c) => _writer.lfsPull(cancel: c));

  /// Downloads every LFS object any ref needs, for working offline.
  Future<void> lfsFetchAll() => _lfsNetwork(
    _l.actLfsFetchAll,
    (c) => _writer.lfsFetchAll(cancel: c),
    lane: _Lane.fetch,
    writesWorkingTree: false,
  );

  /// Downloads one working-tree file's content and checks it out.
  Future<void> lfsDownloadFile(String file) => _lfsNetwork(
    _l.actLfsDownload(file),
    (c) => _writer.lfsPull(include: file, cancel: c),
  );

  /// Downloads the object [file] has at [rev], leaving the working tree alone.
  Future<void> lfsFetchObject(String remote, String rev, String file) =>
      _lfsNetwork(
        _l.actLfsDownload(file),
        (c) => _writer.lfsFetchObject(remote, rev, file, cancel: c),
        lane: _Lane.fetch,
        writesWorkingTree: false,
      );

  /// What a prune would remove. [completed] is true only when the dry run ran
  /// to the end; a failure, a busy-lane skip or a cancel leaves it false (each
  /// already toasted). With [completed] true, a null preview means the report
  /// was unreadable.
  Future<({bool completed, LfsPrunePreview? preview})> lfsPrunePreview() async {
    LfsPrunePreview? preview;
    var completed = false;
    await _lfsNetwork(
      _l.actLfsPrunePreview,
      (c) async {
        final r = await _writer.lfsPruneDryRun(cancel: c);
        if (!r.ok) throw GitException('git lfs prune --dry-run', r);
        preview = parseLfsPruneDryRun('${r.stdout}\n${r.stderr}');
        completed = true;
      },
      writesWorkingTree: false,
      toastSuccess: false,
    );
    return (completed: completed, preview: preview);
  }

  Future<void> lfsPrune() => _lfsNetwork(
    _l.actLfsPrune,
    (c) => _writer.lfsPrune(cancel: c),
    writesWorkingTree: false,
  );

  Future<bool> lfsTrack(String pattern) =>
      _lfsLocal(_l.actLfsTrack(pattern), () => _writer.lfsTrack(pattern));

  Future<bool> lfsTrackFile(String file) =>
      _lfsLocal(_l.actLfsTrack(file), () => _writer.lfsTrackFile(file));

  /// Untracks [pattern] as `git lfs track` lists it, with [source] the
  /// `.gitattributes` file it came from.
  /// Stops routing [pattern], listed from [source], through LFS.
  ///
  /// `git lfs untrack` succeeds without removing some patterns — those
  /// written with escapes, as tracking a single file writes them. So the
  /// listing is read again afterwards, and a pattern still there is removed
  /// from its own `.gitattributes` directly. Nothing is staged either way.
  Future<bool> lfsUntrack(String pattern, String source) {
    final target = lfsUntrackTarget(pattern, source);
    return _lfsLocal(_l.actLfsUntrack(pattern), () async {
      await _writer.lfsUntrack(target.pattern, dir: target.dir);
      final still = parseLfsTrackList(await _writer.lfsTrackList())
          .contains(LfsTrackedPattern(pattern: pattern, source: source));
      if (!still) return;
      final file = p.normalize(p.join(path, source.replaceAll(r'\', '/')));
      if (!p.isWithin(path, file)) {
        throw GitException(_l.actOutsideRepo(source));
      }
      final edited = withoutLfsPattern(
        await File(file).readAsString(),
        target.pattern,
      );
      if (edited == null) {
        throw GitException(_l.actPatternNotRemoved(pattern, source));
      }
      await File(file).writeAsString(edited);
    });
  }

  Future<List<LfsTrackedPattern>> lfsTrackedPatterns() async =>
      parseLfsTrackList(await _writer.lfsTrackList());

  /// Committed files whose current attributes route them through LFS but that
  /// are still stored as regular blobs. Throws [GitException] when git fails,
  /// so callers can report it.
  Future<List<String>> lfsConvertCandidates() async {
    // Which files the attributes reach is git's call, not a glob's: nested
    // .gitattributes, negations and directory patterns all shape it. So list
    // every tracked file and keep those whose filter attribute is lfs.
    final listed = await _git.run(
      ['ls-files', '-z'],
      repoPath: path,
      timeout: lfsReadTimeout,
    );
    if (!listed.ok) throw GitException('git ls-files', listed);
    final files = [
      for (final f in listed.stdout.split('\x00'))
        if (f.isNotEmpty) f,
    ];
    if (files.isEmpty) return const [];
    final attrs = await _git.run(
      ['check-attr', '-z', '--stdin', 'filter'],
      repoPath: path,
      timeout: lfsReadTimeout,
      stdin: '${files.join('\x00')}\x00',
    );
    if (!attrs.ok) throw GitException('git check-attr', attrs);
    // Output is repeated path, attribute, value triples.
    final parts = attrs.stdout.split('\x00');
    final routed = <String>{
      for (var i = 0; i + 2 < parts.length; i += 3)
        if (parts[i + 2] == 'lfs') parts[i],
    };
    final lfs = await _git.run(
      ['lfs', 'ls-files', '-l'],
      repoPath: path,
      timeout: lfsReadTimeout,
    );
    final already = lfs.ok
        ? {for (final e in parseLfsLsFiles(lfs.stdout)) e.path}
        : const <String>{};
    return [
      for (final f in files)
        if (routed.contains(f) && !already.contains(f)) f,
    ];
  }

  /// Stages [files] again through the current attributes, as LFS pointers,
  /// together with the changed `.gitattributes` files behind them. Stops at
  /// staged, as every Mergelio flow does.
  Future<bool> lfsConvert(List<String> files) async {
    // A busy-lane skip inside _network reports true; the caller must not
    // read that as "converted".
    if (_blockedByRepoOp) return false;
    return _lfsNetwork(_l.actLfsConvert, (c) async {
      await _writer.renormalize(files, cancel: c);
      // Pointers staged without the rule that makes them pointers would
      // commit as plain pointer text.
      await _writer.stageGitattributes();
    });
  }

  /// Writes the LFS filters and hooks into this repository. Only ever run on
  /// the user's explicit choice.
  Future<bool> lfsInstallHooks() =>
      _lfsLocal(_l.actLfsInstallHooks, _writer.lfsInstallLocal);

  /// Locks [path] on the LFS server so nobody else can change it.
  Future<bool> lfsLock(String path) {
    if (_blockedByFetchOp) return Future.value(false);
    return _lfsNetwork(
      _l.actLfsLock(path),
      (c) async {
        try {
          await _writer.lfsLock(path, cancel: c);
        } on GitException catch (e) {
          throw _lockRefusal(e, unlock: false);
        }
      },
      lane: _Lane.fetch,
      writesWorkingTree: false,
    );
  }

  /// Releases [lock], which the current user holds.
  Future<bool> lfsUnlock(LfsLock lock) => _lfsUnlock(lock, force: false);

  /// Releases [lock] even when someone else holds it. Does not confirm;
  /// callers ask the user first.
  Future<bool> lfsForceUnlock(LfsLock lock) => _lfsUnlock(lock, force: true);

  Future<bool> _lfsUnlock(LfsLock lock, {required bool force}) {
    if (_blockedByFetchOp) return Future.value(false);
    return _lfsNetwork(
      force ? _l.actLfsForceUnlock(lock.path) : _l.actLfsUnlock(lock.path),
      (c) async {
        try {
          // git-lfs can exit 0 and still report a refusal in the JSON.
          final out = await _writer.lfsUnlock(lock.id, force: force, cancel: c);
          final reason = parseLfsUnlockFailure(out);
          if (reason != null) throw GitException(reason);
        } on GitException catch (e) {
          throw _lockRefusal(e, unlock: true);
        }
      },
      lane: _Lane.fetch,
      writesWorkingTree: false,
    );
  }

  /// git-lfs writes refusal reasons to stdout as JSON, but the failure toast
  /// prefers stderr and falls back to the message, so lift the reason there.
  GitException _lockRefusal(GitException e, {required bool unlock}) {
    if ((e.result?.err ?? '').isNotEmpty) return e;
    final out = e.result?.stdout ?? '';
    if (unlock) {
      final reason = parseLfsUnlockFailure(out);
      return reason == null || reason == 'unlock failed'
          ? e
          : GitException(reason);
    }
    try {
      final v = jsonDecode(out);
      final m = v is Map ? v['message'] : null;
      if (m is String && m.isNotEmpty) return GitException(m);
    } on FormatException {
      // Not JSON; keep the original.
    }
    return e;
  }

  // — Submodules —

  Future<void> submoduleUpdateAll({bool recursive = false}) => _network(
    _l.actSubmoduleUpdateAll,
    (_) => _writer.submoduleUpdate(init: true, recursive: recursive),
  );

  Future<void> submoduleUpdate(String path) => _network(
    _l.actSubmoduleUpdate(path),
    (_) => _writer.submoduleUpdate(path: path, init: true),
  );

  Future<void> submoduleUpdateRemote(String path) => _network(
    _l.actSubmoduleUpdateRemote(path),
    (_) => _writer.submoduleUpdateRemote(path),
  );

  Future<void> submoduleAdd(String url, String path, {String? branch}) =>
      _network(
        _l.actSubmoduleAdd,
        (_) => _writer.submoduleAdd(url, path, branch: branch),
      );

  Future<void> submoduleSync([String? path]) =>
      _network(_l.actSubmoduleSync, (_) => _writer.submoduleSync(path: path));

  Future<void> submoduleDeinit(String path) => _network(
    _l.actSubmoduleDeinit(path),
    (_) => _writer.submoduleDeinit(path, force: true),
  );

  Future<void> submoduleRemove(String path) => _network(
    _l.actSubmoduleRemove(path),
    (_) => _writer.submoduleRemove(path),
  );

  /// Fetch URL for [remote] (read-only; empty if unset).
  Future<String> remoteUrl(String remote) =>
      GitReader(_git, path).remoteUrl(remote);

  Future<void> addRemote(String name, String url) => _undoable(
    _l.actAddRemote(name),
    () => _writer.addRemote(name, url),
    undo: () => _writer.removeRemote(name),
    redo: () => _writer.addRemote(name, url),
  );

  /// Removing a remote also drops its remote-tracking refs; undo restores the
  /// remote's configuration, and a fetch brings the refs back.
  Future<void> removeRemote(String name) async {
    final url = await remoteUrl(name);
    await _undoable(
      _l.actRemoveRemote(name),
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

    await _undoable(_l.actEditRemote(from), forward, undo: back, redo: forward);
  }

  /// Pulls the current branch's upstream. [ffOnly] declines to reconcile a
  /// diverged history rather than writing a merge the user did not ask for;
  /// [autostash] shelves uncommitted work for the duration and puts it back.
  Future<void> pull({
    bool rebase = false,
    bool ffOnly = false,
    bool autostash = false,
  }) async {
    final ok = await _network(
      _l.actPull,
      (cancel) => _writer.pull(
        rebase: rebase,
        ffOnly: ffOnly,
        autostash: autostash,
        cancel: cancel,
      ),
      onSuccess: () {
        _ref.read(forgeRefreshProvider).refreshAfterGitOp(path);
        _bumpLfs();
      },
    );
    // A pull that did not land leaves the reader wherever they were; moving
    // the cursor would lose their place for nothing.
    if (!ok) return;
    // `--quiet --verify` so an unborn branch answers with nothing instead of
    // an error: there is no commit to put the cursor on yet.
    final sha = await _out(['rev-parse', '--quiet', '--verify', 'HEAD']);
    if (sha.isEmpty) return;
    _ref.read(selectedCommitProvider.notifier).state = sha;
  }

  /// Pushes the current branch; false when the push failed, so a step that
  /// should follow only a pushed branch can tell.
  Future<bool> push({bool force = false, String? remote, bool tags = false}) =>
      _network(
        force ? _l.actForcePush : _l.actPush,
        (cancel) => _writer.push(
          force: force,
          remote: remote,
          tags: tags,
          cancel: cancel,
        ),
        writesWorkingTree: false,
        onSuccess: () =>
            _ref.read(forgeRefreshProvider).refreshAfterGitOp(path),
      );

  /// True (and toasts) when a fetch-lane operation is running, so a second
  /// one must not start beside it.
  bool get _blockedByFetchOp {
    if (_ref.read(fetchBusyProvider) == null) return false;
    _ref.read(toastProvider.notifier).show(_l.actBusy, kind: ToastKind.warning);
    return true;
  }

  /// True (and toasts) when something already holds the repository lane, so an
  /// index-touching mutation must not run concurrently and race on
  /// `.git/index.lock`. A running fetch is not that: it holds its own lane.
  bool get _blockedByRepoOp {
    if (_ref.read(busyProvider) == null) return false;
    _ref.read(toastProvider.notifier).show(_l.actBusy, kind: ToastKind.warning);
    return true;
  }

  /// True (and toasts) when a `git bisect run` is walking the range, so no
  /// other bisect command may touch the state it is walking.
  ///
  /// A run is a second git process writing `.git/BISECT_*` and moving HEAD on
  /// its own schedule. A mark landing in the middle of it records a verdict
  /// against whichever commit the run happened to have checked out, and a
  /// reset throws away refs the run is still adding to. The bar takes its own
  /// buttons away while a run is going, but the graph's per-commit menu offers
  /// the same verdicts on every row and the quit dialog offers the same reset,
  /// so the refusal has to live here where all of them arrive.
  bool get _blockedByBisectRun {
    if (_ref.read(bisectRunProvider(path)) == null) return false;
    _ref
        .read(toastProvider.notifier)
        .show(_l.actBisectRunning, kind: ToastKind.warning);
    return true;
  }

  /// Whether a file write has to wait. Only an operation that rewrites the
  /// working tree conflicts with one; a fetch or a push can run for minutes,
  /// and turning a save away for that long would lose the user's typing.
  bool get _blockedByWorkingTreeOp {
    if (_ref.read(busyProvider)?.touchesWorkingTree != true) return false;
    _ref.read(toastProvider.notifier).show(_l.actBusy, kind: ToastKind.warning);
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

  /// Stages exactly [paths] — a selection picked in the Changes panel.
  Future<void> stageFiles(List<String> paths) async {
    if (paths.isEmpty || _blockedByRepoOp) return;
    await _timed(
      'Stage ${paths.length} files',
      () => _writer.stagePaths(paths),
    );
    _refresh();
  }

  /// Unstages exactly [paths], keeping their worktree content.
  Future<void> unstageFiles(List<String> paths) async {
    if (paths.isEmpty || _blockedByRepoOp) return;
    await _timed(
      'Unstage ${paths.length} files',
      () => _writer.unstagePaths(paths),
    );
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

  /// Dry-runs [patch] every way [applyPatchFile] could apply it. Throws
  /// when git finds no patch in it at all; the caller words that for the
  /// user.
  Future<PatchPreview> previewPatch(List<int> patch) async {
    final numstat = await _writer.patchNumstat(patch);
    final worktree = await _writer.checkPatch(patch);
    final stage = await _writer.checkPatch(patch, index: true);
    return PatchPreview(
      files: parsePatchNumstat(numstat),
      subjects: mailboxSubjects(utf8.decode(patch, allowMalformed: true)),
      worktreeOk: worktree.ok,
      stageOk: stage.ok,
      // Only asked for when it would be offered.
      threeWay: worktree.ok
          ? ThreeWayCheck.unavailable
          : threeWayCheckOf(await _writer.checkPatch(patch, threeWay: true)),
      error: worktree.err,
    );
  }

  /// Applies a patch file the user picked. Never commits: a mailbox's
  /// messages and authors are dropped and the result is left for the user to
  /// commit. A direct apply undoes by reversing it; a 3-way merge can leave
  /// conflicts, which nothing reverses, so it records no undo.
  ///
  /// A failure is toasted here like any other git failure; success and
  /// conflicts are left to the caller to announce.
  Future<PatchOutcome> applyPatchFile(List<int> patch, PatchMode mode) async {
    final index = mode == PatchMode.stage;
    if (mode != PatchMode.threeWay) {
      final ok = await _undoable(
        index ? _l.actApplyStagePatch : _l.actApplyPatch,
        () => _writer.applyPatch(patch, index: index),
        undo: () => _writer.applyPatch(patch, index: index, reverse: true),
        redo: () => _writer.applyPatch(patch, index: index),
      );
      return ok ? PatchOutcome.applied : PatchOutcome.failed;
    }
    final label = _l.actApplyPatch3Way;
    if (_blockedByRepoOp) return PatchOutcome.failed;
    _ref.read(busyProvider.notifier).state = BusyState(label);
    final opId = await _journalBegin(label);
    try {
      await _timed(label, () => _writer.applyPatch(patch, threeWay: true));
      await _journalDone(opId);
      return PatchOutcome.applied;
    } on GitException catch (e) {
      // Conflicts are the expected outcome the user chose 3-way for: the
      // patch is in, with unmerged files left to resolve.
      if (e.result?.stderr.contains('with conflicts') ?? false) {
        await _journalDone(opId);
        return PatchOutcome.conflicts;
      }
      await _journalFail(opId);
      _toastErr(label, e);
      return PatchOutcome.failed;
    } on Object {
      // The temp patch file could not be written. Left pending, the entry
      // would read as a crash on the next launch.
      await _journalFail(opId);
      rethrow;
    } finally {
      _ref.read(busyProvider.notifier).state = null;
      _refresh();
    }
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
        _l.actDiscardFile(f.path),
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
      _l.actDiscardFile(f.path),
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

    await _undoable(_l.actDiscardAll, discard, undo: restore, redo: discard);
  }

  /// Discards every uncommitted change to [files] at once: tracked files
  /// revert to HEAD, staged and unstaged alike, and untracked ones are
  /// deleted. One undo entry puts the bytes back and re-stages what was
  /// staged, as [discardAll] does for the whole tree.
  Future<void> discardFiles(List<WorkingFile> files) async {
    if (files.isEmpty || _blockedByRepoOp) return;
    // A rename is undone through both names: the old one comes back.
    final tracked = [
      for (final f in files)
        if (!f.isUntracked) ...[f.path, ?f.origPath],
    ];
    final untracked = [
      for (final f in files)
        if (f.isUntracked) f.path,
    ];

    final before = <String, List<int>?>{};
    for (final p in {...tracked, ...untracked}) {
      final file = File('$path/$p');
      before[p] = await file.exists() ? await file.readAsBytes() : null;
    }
    // Literal, like the discard itself: a file named `*.txt` must not pull
    // other files' staged changes into the patch undo re-applies.
    final stagedPatch = tracked.isEmpty
        ? ''
        : (await _git.run([
            '--literal-pathspecs',
            'diff',
            '--cached',
            '--',
            ...tracked,
          ], repoPath: path)).stdout;

    Future<void> discard() async {
      await _writer.restorePathsFromHead(tracked);
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
      _l.actDiscardFiles(files.length),
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
      _l.actDiscardHunk,
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
        _l.actEditFile(relPath),
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
            _l.actCouldNotSave(relPath),
            description: e.osError?.message ?? e.message,
            kind: ToastKind.error,
          );
      return false;
    }
    return saved;
  }

  /// The repo-relative directory of the closest `.gitignore` above [relPath],
  /// not counting the one at the root. Null when there is none.
  Future<String?> nearestIgnoreDir(String relPath) async {
    if (!isRepoRelativePath(relPath)) return null;
    for (final d in ancestorDirs(relPath)) {
      if (await File('$path/$d/.gitignore').exists()) return d;
    }
    return null;
  }

  /// Appends a rule ignoring [relPath] at [scope] to the [target] ignore
  /// file, creating it when missing. Only ever appends; undo puts back the
  /// exact bytes from before, or removes a file this created. Nothing is
  /// staged. A rule already in the file is reported and not written again.
  ///
  /// Returns whether the path is now covered by the rule.
  Future<bool> addIgnoreRule(
    String relPath,
    IgnoreScope scope,
    IgnoreTarget target,
  ) async {
    if (_blockedByWorkingTreeOp) return false;
    if (!isRepoRelativePath(relPath)) return false;
    final String baseDir;
    final File file;
    switch (target) {
      case IgnoreTarget.root:
        baseDir = '';
        file = File('$path/.gitignore');
      case IgnoreTarget.nearest:
        final d = await nearestIgnoreDir(relPath);
        if (d == null) return false;
        baseDir = d;
        file = File('$path/$d/.gitignore');
      case IgnoreTarget.exclude:
        // Git names it, so a linked worktree gets the shared exclude file.
        final at = await _stateFilePath('info/exclude');
        if (at == null) return false;
        baseDir = '';
        file = File(at);
    }
    // A .gitignore symlinked out of the repository must not be written
    // through. A dangling link reads as no file at all, yet appending to it
    // would create its target, so links are checked without following them.
    // The exclude file is skipped on purpose: a linked worktree shares the
    // main repository's, which lies outside this working tree.
    if (target != IgnoreTarget.exclude &&
        (await file.exists() || await FileSystemEntity.isLink(file.path)) &&
        !isInsideRepo(path, file.path)) {
      return false;
    }
    final rule = ignoreRule(relPath, scope, baseDir: baseDir);
    if (rule == null) return false;
    final name = p.relative(file.path, from: path);
    try {
      final before = await file.exists() ? await file.readAsBytes() : null;
      final existing = before == null
          ? ''
          : utf8.decode(before, allowMalformed: true);
      final appended = appendIgnoreRule(existing, rule);
      if (appended == null) {
        _ref
            .read(toastProvider.notifier)
            .show(_l.actAlreadyIgnored(rule, name), kind: ToastKind.info);
        return true;
      }
      // Appending, not rewriting, keeps whatever bytes are already there
      // exactly as they were.
      final tail = appended.substring(existing.length);
      Future<void> write() async {
        await file.parent.create(recursive: true);
        await file.writeAsString(tail, mode: FileMode.append);
      }

      var written = false;
      await _undoable(
        _l.actIgnore(rule),
        () async {
          await write();
          written = true;
        },
        undo: () async {
          if (before != null) {
            await file.writeAsBytes(before);
          } else if (await file.exists()) {
            await file.delete();
          }
        },
        redo: write,
        // Only an ignore file is written, which no git lock guards.
        claimsRepo: false,
      );
      return written;
    } on FileSystemException catch (e) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actCouldNotWrite(name),
            description: e.osError?.message ?? e.message,
            kind: ToastKind.error,
          );
      return false;
    }
  }

  /// Commits what is staged and reports how it went. A hook's refusal comes
  /// back in the outcome rather than as a toast, so the caller can show the
  /// hook's own output; every other failure is toasted as usual.
  Future<CommitOutcome> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    bool noVerify = false,
    bool signoff = false,
    List<String> coauthors = const [],
    List<CommitTrailer> trailers = const [],
  }) async {
    if (_blockedByRepoOp) return const CommitOutcome();
    final profile = _ref.read(profilesProvider).active;
    // HEAD before the commit — undo soft-resets here, returning the committed
    // changes to the staging area (works for amend too: prev is the original).
    final prev = await _headSha();
    // Committing while MERGE_HEAD is set is what closes a merge and gives the
    // commit its second parent.
    final merging = await _stateFileExists('MERGE_HEAD');
    String? merged;
    // Only the first run can be cancelled; a redo has no busy bar to show it.
    final cancel = GitCancel();
    Future<void> doCommit({GitCancel? cancel}) async {
      await _writer.commit(
        summary,
        description: description,
        amend: amend,
        sign: sign,
        noVerify: noVerify,
        signoff: signoff,
        coauthors: coauthors,
        trailers: trailers,
        authorName: profile?.name,
        authorEmail: profile?.email,
        cancel: cancel,
      );
      if (merging) merged = await _headSha();
    }

    HookRejectedException? rejection;
    final committed = await _undoable(
      amend
          ? _l.actAmendCommit
          : merging
          ? _l.actMergeCommit
          : _l.actCommit,
      () => doCommit(cancel: cancel),
      cancel: cancel,
      undo: () => _writer.resetSoft(prev),
      // The changes are staged again after undo, so redo just re-commits — but
      // not for a merge, whose second parent went with MERGE_HEAD. That one is
      // restored from the reflog.
      redo: () => merged == null ? doCommit() : _writer.resetHard(merged!),
      handled: (e) {
        if (e is! HookRejectedException) return false;
        rejection = e;
        return true;
      },
    );
    if (merging && committed) {
      _ref.read(_opBaseProvider(path).notifier).state = null;
    }
    return CommitOutcome(committed: committed, rejection: rejection);
  }

  // --- Undoable ref operations ----------------------------------------------

  GitService get _git => _tracked ?? _ref.read(gitServiceProvider);
  Future<String> _out(List<String> args) async =>
      (await _git.run(args, repoPath: path)).out;

  Future<String> _headSha() => _out(['rev-parse', 'HEAD']);

  /// Current branch name, or the commit sha in detached HEAD.
  Future<String> _headRef() async {
    final name = await _out(['rev-parse', '--abbrev-ref', 'HEAD']);
    return name == 'HEAD' ? await _headSha() : name;
  }

  /// Reports a failed op to the user.
  ///
  /// Takes any error rather than only a [GitException]: git is not the only
  /// thing an op touches, and an error that reaches here has nowhere else to
  /// land — most of these run from a button nobody awaits, where anything
  /// not reported is never seen at all.
  void _toastErr(String label, Object e) {
    final String description;
    if (e is GitException) {
      // Stderr first: it is what git itself said, where the exception's own
      // message is only the wrapper this code put around it.
      final err = e.result?.err ?? '';
      description = err.isNotEmpty ? err : e.message;
    } else {
      description = '$e';
    }
    // A hook's refusal carries only the hook's own output; the title says
    // whose it is.
    final title = e is HookRejectedException
        ? _l.actHookStopped(e.hook, label)
        : _l.actFailed(label);
    _ref
        .read(toastProvider.notifier)
        .show(title, description: description, kind: ToastKind.error);
  }

  /// Runs an undoable op: executes [run], records its inverse, refreshes. The
  /// recorded undo/redo re-run real git and refresh, so the UI follows.
  /// Reports whether [run] went through. A failure [handled] claims is left
  /// to the caller instead of being toasted.
  Future<bool> _undoable(
    String label,
    Future<void> Function() run, {
    required Future<void> Function() undo,
    required Future<void> Function() redo,
    // Set false by an op that writes a working-tree file and nothing else: it
    // needs no lock of its own and must not take the one a running op holds.
    bool claimsRepo = true,
    bool Function(GitException)? handled,
    // Puts Cancel on the busy bar, for an op that runs the user's hooks and so
    // can wait on them for as long as they take.
    GitCancel? cancel,
  }) async {
    if (claimsRepo) {
      if (_blockedByRepoOp) return false;
      // Hold the shared busy flag so a second ref op (or network op) cannot
      // run concurrently and race on .git/index.lock.
      _ref.read(busyProvider.notifier).state = BusyState(
        label,
        onCancel: cancel?.cancel,
      );
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
      return true;
    } on GitCancelledException {
      await _journalFail(opId);
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show(_l.actCancelled(label), kind: ToastKind.warning);
      return false;
    } on GitException catch (e) {
      // Refresh on failure too: a conflicted cherry-pick/revert leaves the
      // repo mid-operation, which the UI must show.
      await _journalFail(opId);
      _refresh();
      if (handled?.call(e) != true) _toastErr(label, e);
      return false;
    } on Object {
      // A file write fails with a FileSystemException the caller reports.
      // Left pending, the entry would read as a crash on the next launch.
      await _journalFail(opId);
      rethrow;
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
      throw GitException(_l.actUndoDirty);
    }
    await _writer.resetHard(prev);
  }

  Future<void> undo() async {
    if (_blockedByRepoOp) return;
    _ref.read(busyProvider.notifier).state = BusyState(_l.actUndo);
    try {
      await _timed('Undo', _ref.read(undoProvider(path).notifier).undo);
    } on GitException catch (e) {
      _toastErr(_l.actUndo, e);
    } on Object catch (e) {
      // File-edit undo entries do filesystem writes, which can fail with
      // more than GitException; surface it rather than crash.
      _ref
          .read(toastProvider.notifier)
          .show(_l.actUndoFailed, description: '$e', kind: ToastKind.error);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  Future<void> redo() async {
    if (_blockedByRepoOp) return;
    _ref.read(busyProvider.notifier).state = BusyState(_l.actRedo);
    try {
      await _timed('Redo', _ref.read(undoProvider(path).notifier).redo);
    } on GitException catch (e) {
      _toastErr(_l.actRedo, e);
    } on Object catch (e) {
      _ref
          .read(toastProvider.notifier)
          .show(_l.actRedoFailed, description: '$e', kind: ToastKind.error);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Whether writing [target]'s files can mean downloading them: git-lfs is
  /// installed, and LFS attributes are in the working tree or at [target].
  /// Either side counts, as a branch can start or stop using LFS.
  Future<bool> _lfsInPlay(String target) async {
    if (await _ref.read(lfsToolProvider.future) == null) return false;
    Future<String> version() => _ref.read(gitVersionProvider.future);
    // Both asked at once: this sits in front of every checkout.
    final found = await Future.wait([
      lfsAttributesAt(_git, LfsSource(repoPath: path), gitVersion: version),
      lfsAttributesAt(
        _git,
        LfsSource(repoPath: path, rev: target),
        gitVersion: version,
      ),
    ]);
    return found.contains(true);
  }

  /// Runs [op], a checkout to [to] that [cancel] can stop. A cancel that
  /// stopped it before HEAD moved has left the files it already wrote looking
  /// like the user's own edits, and git would refuse a retry over them, so
  /// they are put back before the cancel is reported. Without a [cancel] there
  /// is nothing to put back, and HEAD is not even read.
  ///
  /// git moves HEAD only once the tree is written, and runs the post-checkout
  /// hook after that; a cancel that lands in the hook leaves a finished
  /// checkout, which returns normally (check [GitCancel.isCancelled]).
  Future<void> _checkoutPuttingBack(
    String to,
    GitCancel? cancel,
    Future<void> Function() op,
  ) async {
    if (cancel == null) return op();
    final fromSha = await _headSha();
    final fromRef = await _headRef();
    try {
      await op();
    } on GitCancelledException {
      if (await _headSha() != fromSha || await _headRef() != fromRef) return;
      if (fromSha.isEmpty) rethrow;
      try {
        await _writer.restorePartialCheckout(fromSha, to);
      } on Object catch (e) {
        // The cancel is still what happened; files left over show as changes.
        appLog.warn(
          'Putting back a cancelled checkout failed: $e',
          scope: path,
        );
      }
      rethrow;
    }
  }

  /// In a repository using LFS, a checkout downloads what it writes, so it
  /// gets the transfer ceiling and a Cancel; anywhere else it is quick.
  Future<void> checkout(String ref, {bool ignoreOtherWorktrees = false}) async {
    final prev = await _headRef();
    final lfs = await _lfsInPlay(ref);
    final timeout = lfs ? GitWriter.lfsTransferTimeout : null;
    // Only the first run can be cancelled; undo and redo have no busy bar.
    final cancel = lfs ? GitCancel() : null;
    await _undoable(
      _l.actCheckout(ref),
      () => _checkoutPuttingBack(
        ref,
        cancel,
        () => _writer.checkout(
          ref,
          ignoreOtherWorktrees: ignoreOtherWorktrees,
          timeout: timeout,
          cancel: cancel,
        ),
      ),
      cancel: cancel,
      undo: () => _writer.checkout(prev, timeout: timeout),
      redo: () => _writer.checkout(
        ref,
        ignoreOtherWorktrees: ignoreOtherWorktrees,
        timeout: timeout,
      ),
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
    final lfs = await _lfsInPlay(rb.name);
    final timeout = lfs ? GitWriter.lfsTransferTimeout : null;
    final cancel = lfs ? GitCancel() : null;
    await _undoable(
      _l.actCheckout(rb.name),
      () => _checkoutPuttingBack(
        rb.name,
        cancel,
        () => _writer.checkoutTracking(
          rb.remote,
          rb.branch,
          timeout: timeout,
          cancel: cancel,
        ),
      ),
      cancel: cancel,
      undo: () async {
        await _writer.checkout(prev, timeout: timeout);
        await _writer.deleteBranch(rb.branch, force: true);
      },
      redo: () =>
          _writer.checkoutTracking(rb.remote, rb.branch, timeout: timeout),
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
      _l.actResetBranchTo(rb.branch, rb.name),
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
    final timeout = await _lfsInPlay(rb.branch)
        ? GitWriter.lfsTransferTimeout
        : null;
    if ((await _out(['status', '--porcelain'])).isNotEmpty) {
      await _writer.stashPush(
        const StashPushOptions(message: 'auto-stash before switch'),
        timeout,
      );
      ref = 'stash@{0}';
    }
    await _writer.checkout(
      rb.branch,
      ignoreOtherWorktrees: ignoreOtherWorktrees,
      timeout: timeout,
    );
    await _writer.resetHard('${rb.remote}/${rb.branch}');
    return ref;
  }

  Future<void> createBranch(String name, {String? at}) async {
    // Resolve the target now so redo can recreate the branch even after undo
    // deleted it (the branch name no longer resolves at that point).
    final target = at ?? await _headSha();
    await _undoable(
      _l.actCreateBranch(name),
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
      _l.actDeleteBranch(name),
      () => _writer.deleteBranch(name),
      undo: () => _writer.createBranch(name, at: sha),
      redo: () => _writer.deleteBranch(name),
    );
  }

  /// Deletes several local branches as one undoable step. A branch git
  /// refuses does not stop the others, and undo restores exactly the ones
  /// that went.
  ///
  /// Every delete is `-D`. Unmerged branches need it, and the caller has had
  /// the user confirm each by name. Merged ones were found merged into
  /// [trunk], which `-d` cannot check: it measures against HEAD or the
  /// upstream, and refuses a branch merged into the trunk whenever something
  /// else is checked out. So the trunk check is repeated here on the tip
  /// about to go, and a branch that has since moved off it is kept.
  Future<void> deleteBranches(
    List<HygieneBranch> branches, {
    required String? trunk,
  }) async {
    if (branches.isEmpty) return;
    // One listing rather than `rev-parse` of every name: rev-parse fails
    // outright on the first name that no longer resolves, and one branch
    // deleted elsewhere since the list was read must not cost all the others.
    final r = await _git.run([
      'for-each-ref',
      '--format=%(refname)%09%(objectname)',
      'refs/heads',
    ], repoPath: path);
    if (!r.ok) {
      _toastErr(_l.actDeleteBranchesLabel, GitException('git for-each-ref', r));
      return;
    }
    final tips = <String, String>{
      for (final line in const LineSplitter().convert(r.stdout))
        if (line.startsWith('refs/heads/') && line.contains('\t'))
          line.substring(11, line.indexOf('\t')): line.substring(
            line.indexOf('\t') + 1,
          ),
    };
    final deleted = <(String, String)>[];
    final refused = <String>[];
    Future<void> forward() async {
      for (final b in branches) {
        final sha = tips[b.name];
        if (sha == null) {
          refused.add(_l.actBranchGone(b.name));
          continue;
        }
        if (!b.needsForce) {
          final still =
              trunk != null &&
              (await _git.run([
                'merge-base',
                '--is-ancestor',
                sha,
                'refs/heads/$trunk',
              ], repoPath: path)).ok;
          if (!still) {
            refused.add(_l.actBranchNotMerged(b.name, trunk ?? 'HEAD'));
            continue;
          }
        }
        try {
          await _writer.deleteBranch(b.name, force: true);
          deleted.add((b.name, sha));
        } on GitException catch (e) {
          final err = e.result?.err ?? '';
          refused.add(err.isNotEmpty ? err : '${b.name}: ${e.message}');
        }
      }
      // Nothing went, so there is nothing to undo: fail the op instead.
      if (deleted.isEmpty) throw GitException(refused.join('\n'));
    }

    await _undoable(
      branches.length == 1
          ? _l.actDeleteBranch(branches.single.name)
          : _l.actDeleteBranches(branches.length),
      forward,
      undo: () async {
        for (final (name, sha) in deleted) {
          await _writer.createBranch(name, at: sha);
        }
      },
      redo: () async {
        for (final (name, _) in deleted) {
          await _writer.deleteBranch(name, force: true);
        }
      },
    );
    if (deleted.isNotEmpty && refused.isNotEmpty) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actSomeNotDeleted,
            description: refused.join('\n'),
            kind: ToastKind.warning,
          );
    }
  }

  /// `git gc`. True when it ran to the end.
  Future<bool> runGc() => _housekeeping(_l.actRunGc, _writer.gc);

  /// `git maintenance run`. True when it ran to the end.
  Future<bool> runMaintenance() =>
      _housekeeping(_l.actRunMaintenance, _writer.maintenanceRun);

  /// Holds the repository lane but leaves file saves alone: housekeeping
  /// repacks objects and refs and never touches the working tree. Refused
  /// while a fetch runs, since repacking beside a fetch that is still writing
  /// packs can drop what the fetch just brought in.
  Future<bool> _housekeeping(
    String label,
    Future<void> Function({GitCancel? cancel}) op,
  ) async {
    if (_blockedByFetchOp) return false;
    var finished = false;
    await _network(label, (cancel) async {
      await op(cancel: cancel);
      finished = true;
    }, writesWorkingTree: false);
    return finished;
  }

  /// Deletes the branch behind [rb] on its remote. No undo entry: re-pushing
  /// the old sha would resurrect a ref that someone else may have moved on
  /// since, which is not the same thing as putting it back.
  Future<void> deleteRemoteBranch(RemoteBranch rb) => _network(
    _l.actDeleteRef(rb.name),
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
      _l.actDeleteRef(upstream),
      (cancel) => _writer.deleteRemoteBranch(
        upstream.substring(0, slash),
        upstream.substring(slash + 1),
        cancel: cancel,
      ),
      writesWorkingTree: false,
      failureTitle: _l.actDeletedLocalOnly(name, upstream),
    );
  }

  Future<bool> _branchExists(String name) async => (await _git.run([
    'rev-parse',
    '--verify',
    '--quiet',
    'refs/heads/$name',
  ], repoPath: path)).ok;

  Future<void> renameBranch(String from, String to) => _undoable(
    _l.actRenameBranch(from, to),
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
      _toastErr(_l.actSetUpstream, e);
    }
  }

  /// Creates tag [name]; [sign] signs it, with [signingKey] or git's own.
  /// The tagger is the active profile, as for a commit.
  Future<void> createTag(
    String name, {
    String? at,
    String? message,
    bool sign = false,
    String? signingKey,
  }) async {
    final target = at ?? await _headSha();
    final id = _identity;
    // Signing waits on the signer for as long as it takes (a passphrase
    // prompt, say), so only a signed create needs a way out.
    final cancel = sign ? GitCancel() : null;
    Future<void> create({GitCancel? cancel}) => _writer.createTag(
      name,
      at: target,
      message: message,
      sign: sign,
      signingKey: signingKey,
      authorName: id.name,
      authorEmail: id.email,
      cancel: cancel,
    );
    await _undoable(
      _l.actCreateTag(name),
      () => create(cancel: cancel),
      cancel: cancel,
      undo: () => _writer.deleteTag(name),
      redo: create,
    );
  }

  Future<void> deleteTag(String name) async {
    // The ref's own object: for an annotated tag that is the tag object, so
    // undo brings back its message, tagger and signature, not a bare pointer.
    final object = await _out(['rev-parse', 'refs/tags/$name']);
    await _undoable(
      _l.actDeleteTag(name),
      () => _writer.deleteTag(name),
      undo: () => _writer.restoreTag(name, object),
      redo: () => _writer.deleteTag(name),
    );
  }

  /// Cherry-picks [sha]. [mainline] is the 1-based parent to replay the merge
  /// against, and must be given when [sha] is a merge commit — the caller picks
  /// it, since only the user knows which side of the merge they want.
  Future<void> cherryPick(String sha, {int? mainline}) => _sequencerOp(
    label: _l.actCherryPick(_short(sha)),
    branch: _short(sha),
    kind: MergeKind.cherryPick,
    op: () => _writer.cherryPick(sha, mainline: mainline),
    abort: _writer.cherryPickAbort,
  );

  /// Cherry-picks [shas] in the order given — oldest first, as the graph
  /// orders them — in one sequence. Committing, it runs like a single pick:
  /// one undo entry for the whole run, and a conflict pauses the rest of the
  /// sequence for the Merge Tool. With [noCommit] the picks land staged for
  /// the user to commit. Merge commits cannot ride along: each would need its
  /// own mainline parent, so they are refused here and picked one at a time.
  ///
  /// True once the picks landed or wait paused in the Merge Tool; false when
  /// nothing changed — refused, or backed out after a failure — so the caller
  /// can keep the selection for another go.
  Future<bool> cherryPickMany(
    List<String> shas, {
    bool noCommit = false,
  }) async {
    if (shas.isEmpty) return false;
    final merges = (await _out(['rev-list', '--no-walk', '--merges', ...shas]))
        .trim();
    if (merges.isNotEmpty) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actMergesNotTogether,
            description: _l.actMergePickAlone(_short(merges.split('\n').first)),
            kind: ToastKind.warning,
          );
      return false;
    }
    if (noCommit) return _pickStaged(shas);
    return _sequencerOp(
      label: shas.length == 1
          ? _l.actCherryPick(_short(shas.single))
          : _l.actCherryPickN(shas.length),
      branch: _short(shas.first),
      kind: MergeKind.cherryPick,
      op: () => _writer.cherryPickAll(shas),
      abort: _writer.cherryPickAbort,
    );
  }

  /// Applies [shas] to the index and working tree without committing; the user
  /// reviews the staged result and commits it.
  ///
  /// git cannot resume a no-commit run that stopped on a conflict: it leaves
  /// no CHERRY_PICK_HEAD, and `--continue` refuses over the changes the earlier
  /// picks already applied. So a conflict backs the whole run out instead, and
  /// since backing out resets tracked files, the run demands a clean tree
  /// first. Nothing is recorded for undo: the result is ordinary staged
  /// changes, discarded like any other.
  Future<bool> _pickStaged(List<String> shas) async {
    if (_blockedByRepoOp) return false;
    if (await _refuseOverUnfinishedPick()) return false;
    final toast = _ref.read(toastProvider.notifier);
    if ((await _out(['status', '--porcelain', '--untracked-files=no']))
        .isNotEmpty) {
      toast.show(
        _l.actUncommittedChanges,
        description: _l.actPickNoCommitDirty,
        kind: ToastKind.warning,
      );
      return false;
    }
    final n = shas.length;
    final label = n == 1
        ? _l.actCherryPickNoCommit(_short(shas.single))
        : _l.actCherryPickNoCommitN(n);
    final prev = await _headSha();
    _ref.read(busyProvider.notifier).state = BusyState(label);
    final opId = await _journalBegin(label);
    try {
      await _timed(label, () => _writer.cherryPickAll(shas, noCommit: true));
      await _journalDone(opId);
      _refresh();
      toast.show(
        n == 1 ? _l.actPicked(_short(shas.single)) : _l.actPickedN(n),
        description: _l.actPickedStaged,
        kind: ToastKind.success,
      );
      return true;
    } on GitException catch (e) {
      await _journalFail(opId);
      final conflicted = (await _conflictFiles()).isNotEmpty;
      // A run of several leaves a sequence to abort; a lone pick leaves only
      // its conflicts, which a reset to the untouched HEAD clears.
      final backedOut = await _backOut(() async {
        if (await _sequencerDirExists()) {
          await _writer.cherryPickAbort();
        } else if (conflicted) {
          await _writer.resetHard(prev);
        }
      });
      _refresh();
      if (!backedOut) {
        _toastErr(label, e);
        return true;
      }
      if (conflicted) {
        toast.show(
          _l.actNothingPicked,
          description: _l.actPickOneByOne,
          kind: ToastKind.warning,
        );
      } else {
        _toastErr(label, e);
      }
      return false;
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Runs [cleanup] after a failed pick or revert, and says whether it left
  /// the repository as it was. A cleanup that fails itself must not escape:
  /// the caller still owes the user the original error, and the guard on the
  /// next pick catches whatever state was left behind.
  Future<bool> _backOut(Future<void> Function() cleanup) async {
    try {
      await cleanup();
      return true;
    } on GitException {
      return false;
    }
  }

  /// Whether git holds a multi-commit pick or revert sequence. Unlike
  /// CHERRY_PICK_HEAD it outlives a conflict in a no-commit run.
  Future<bool> _sequencerDirExists() async {
    final p = await _stateFilePath('sequencer');
    return p != null && Directory(p).existsSync();
  }

  /// Reverts [sha], with the same [mainline] requirement for merge commits.
  Future<void> revert(String sha, {int? mainline}) => _sequencerOp(
    label: _l.actRevert(_short(sha)),
    branch: _short(sha),
    kind: MergeKind.revert,
    op: () => _writer.revert(sha, mainline: mainline),
    abort: _writer.revertAbort,
  );

  /// Runs a cherry-pick or revert. A clean run records an undo entry; a run
  /// that stops on conflicts hands the paused sequence to the Merge Tool, so
  /// resolving there can continue it in-app instead of stranding the
  /// repository. A failure that left nothing conflicted (a dirty tree, a bad
  /// ref) backs out of any sequence git did start and toasts.
  ///
  /// True when the run landed or paused on conflicts; false when nothing
  /// changed.
  Future<bool> _sequencerOp({
    required String label,
    required String branch,
    required MergeKind kind,
    required Future<void> Function() op,
    required Future<void> Function() abort,
  }) async {
    if (_blockedByRepoOp) return false;
    if (await _refuseOverUnfinishedPick()) return false;
    final prev = await _headSha();
    _ref.read(busyProvider.notifier).state = BusyState(label);
    final opId = await _journalBegin(label);
    try {
      await _timed(label, op);
      await _journalDone(opId);
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
                await op();
                _refresh();
              },
            ),
          );
      _refresh();
      return true;
    } on GitException catch (e) {
      await _journalFail(opId);
      final conflicts = await _conflictFiles();
      if (conflicts.isEmpty) {
        // A run of several that stops partway without a conflict (an
        // untracked file in the way) keeps the picks it already committed and
        // leaves only the sequencer directory behind — no CHERRY_PICK_HEAD.
        // Abort that too, or the repository is stuck mid-sequence.
        final backedOut = await _backOut(() async {
          if (await _sequencerInProgress() || await _sequencerDirExists()) {
            await abort();
          }
        });
        _refresh();
        _toastErr(label, e);
        return !backedOut;
      }
      // A sequence of several picks stops on whichever one conflicts; name
      // that one rather than the first.
      final stopped = await _sequencerHeadLabel(kind);
      _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
        branch: stopped.isEmpty ? branch : stopped,
        prevSha: prev,
        kind: kind,
        files: conflicts,
      );
      _refresh();
      return true;
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Stops a new pick or revert from starting over an unfinished one, and says
  /// so. git refuses to start a pick over an unfinished one, and that refusal
  /// arrives as a failure with the *previous* op's conflicts still in the
  /// tree — which would relabel the open session with this commit. Stop here
  /// instead, and offer the way back to the resolution.
  ///
  /// A sequence directory with no CHERRY_PICK_HEAD — a run stopped by
  /// something other than a conflict, outside the app — has nothing to
  /// resolve, so it gets its own word.
  Future<bool> _refuseOverUnfinishedPick() async {
    if (_ref.read(mergeSessionProvider(path)) == null &&
        !await _sequencerInProgress() &&
        (await GitReader(_git, path).conflictedFiles()).isEmpty) {
      if (!await _sequencerDirExists()) return false;
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actSequencerUnfinished,
            description: _l.actSequencerFinishFirst,
            kind: ToastKind.warning,
          );
      return true;
    }
    _ref
        .read(toastProvider.notifier)
        .show(
          _l.actUnresolvedConflicts,
          description: _l.actFinishResolution,
          kind: ToastKind.warning,
          action: ToastAction(_l.actResolveButton, () {
            openConflictResolution();
          }),
        );
    return true;
  }

  /// The kind of sequencer operation the repository sits in the middle of, or
  /// null when none. Asks git for the state file's path rather than assuming
  /// `.git/`, which is wrong inside a linked worktree.
  Future<MergeKind?> _sequencerKind() async {
    const heads = {
      'CHERRY_PICK_HEAD': MergeKind.cherryPick,
      'REVERT_HEAD': MergeKind.revert,
    };
    for (final e in heads.entries) {
      if (await _stateFileExists(e.key)) return e.value;
    }
    return null;
  }

  /// Absolute path of a git state file (`MERGE_HEAD`, `MERGE_MSG`, ...), or
  /// null when git names none.
  Future<String?> _stateFilePath(String name) async {
    final p = (await _out(['rev-parse', '--git-path', name])).trim();
    if (p.isEmpty) return null;
    return p.startsWith('/') ? p : '$path/$p';
  }

  Future<bool> _stateFileExists(String name) async {
    final p = await _stateFilePath(name);
    return p != null && File(p).existsSync();
  }

  Future<bool> _sequencerInProgress() async => await _sequencerKind() != null;

  Future<void> resetHard(String sha) =>
      _resetTo(sha, _l.actResetTo(_short(sha)));

  /// Moves the current branch to [sha] with git's default `--mixed`: the
  /// commits' content stays on disk as unstaged edits, so nothing is lost.
  Future<void> resetMixed(String sha) async {
    final prev = await _headSha();
    // The index is captured as a tree so undo can put back exactly what was
    // staged; a soft reset alone would restore HEAD and leave it unstaged.
    final index = (await _out(['write-tree'])).trim();
    // An unmerged index has no tree to write, which would leave undo unable to
    // put the staging area back. Refuse the reset rather than undo it halfway.
    if (index.isEmpty) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actCannotResetConflicts,
            description: _l.actFinishOpFirst,
            kind: ToastKind.warning,
          );
      return;
    }
    Future<void> run() => _writer.resetMixed(sha);
    await _undoable(
      _l.actResetToMixed(_short(sha)),
      run,
      undo: () async {
        await _writer.resetSoft(prev);
        await _out(['read-tree', index]);
      },
      redo: run,
    );
  }

  /// Moves the current branch to [sha] with `--soft`: the commits' changes
  /// stay staged.
  Future<void> resetSoft(String sha) async {
    final prev = await _headSha();
    await _undoable(
      _l.actResetToSoft(_short(sha)),
      () => _writer.resetSoft(sha),
      undo: () => _writer.resetSoft(prev),
      redo: () => _writer.resetSoft(sha),
    );
  }

  /// True when [ancestor] is reachable from [descendant] (or is it).
  Future<bool> isAncestor(String ancestor, String descendant) async =>
      (await _git.run([
        'merge-base',
        '--is-ancestor',
        ancestor,
        descendant,
      ], repoPath: path)).ok;

  /// Points branch [name] at [sha] without switching to it (drag-and-drop
  /// "move here"). The current branch is refused: moving it would leave the
  /// working tree out of step, which is what a reset is for.
  Future<void> moveBranch(String name, String sha) async {
    if (await _headRef() == name) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actCannotMoveCurrent,
            description: _l.actResetInstead,
            kind: ToastKind.warning,
          );
      return;
    }
    final prev = await _out(['rev-parse', name]);
    // Resolved now so redo lands where the user dropped, even if [sha] is a
    // branch name that has moved since.
    final to = await _out(['rev-parse', sha]);
    await _undoable(
      _l.actMoveBranch(name, _short(sha)),
      () => _writer.forceBranch(name, to),
      undo: () => _writer.forceBranch(name, prev),
      redo: () => _writer.forceBranch(name, to),
    );
  }

  /// Fast-forwards branch [target] to [to]. The current branch goes through
  /// `merge --ff-only` so its working tree follows; any other branch only has
  /// its ref moved. A [target] that has diverged from [to] is left alone.
  Future<void> fastForward(String target, String to) async {
    if (!await isAncestor(target, to)) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actCannotFastForward(target),
            description: _l.actHasCommitsNotIn(target, to),
            kind: ToastKind.warning,
          );
      return;
    }
    if (await _headRef() != target) {
      final prev = await _out(['rev-parse', target]);
      final sha = await _out(['rev-parse', to]);
      await _undoable(
        _l.actFastForward(target, to),
        () => _writer.forceBranch(target, sha),
        undo: () => _writer.forceBranch(target, prev),
        redo: () => _writer.forceBranch(target, sha),
      );
      return;
    }
    final prev = await _headSha();
    await _undoable(
      _l.actFastForward(target, to),
      () => _writer.mergeFfOnly(to),
      undo: () => _undoReset(prev),
      redo: () => _writer.mergeFfOnly(to),
    );
  }

  /// Switches to [branch] then cherry-picks [sha] onto it (drag-and-drop). One
  /// undo entry (the pick); the switch is not undoable on its own, so a pick
  /// that conflicts or is undone still leaves HEAD on [branch].
  Future<void> cherryPickOnto(String branch, String sha) async {
    if (await _switchTo(branch)) await cherryPick(sha);
  }

  /// Resets the current branch to a remote-tracking ref (e.g. `origin/x`),
  /// discarding any unpushed commits. Uncommitted work is auto-stashed and the
  /// whole reset is undoable, exactly like [resetHard].
  Future<void> resetToRemote(String ref) => _resetTo(ref, _l.actResetTo(ref));

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
      await _writer.stashPush(
        const StashPushOptions(message: 'auto-stash before reset'),
        await _lfsInPlay('HEAD') ? GitWriter.lfsTransferTimeout : null,
      );
      ref = 'stash@{0}';
    }
    await _writer.resetHard(sha);
    return ref;
  }

  Future<void> pushTag(String name) => _network(
    _l.actPushTag(name),
    (cancel) => _writer.pushTag(name, cancel: cancel),
    writesWorkingTree: false,
  );

  /// Deletes tag [name] on [remote]. Deliberately outside the undo journal:
  /// nothing local moves, and an undo entry here would promise to put a ref
  /// back on a remote that other people may have already re-synced against.
  Future<void> deleteRemoteTag(String name, {String remote = 'origin'}) =>
      _network(
        _l.actDeleteRemoteTag(name, remote),
        (cancel) =>
            _writer.deleteRemoteTag(name, remote: remote, cancel: cancel),
        writesWorkingTree: false,
      );

  // — Notes —

  /// The note on [sha] as git has it now, or null when there is none.
  Future<String?> note(String sha) => GitReader(_git, path).note(sha);

  /// Makes [text] the note on [sha]; empty text removes it. Text git would
  /// store unchanged writes nothing, so it leaves no undo entry either. The
  /// note is authored by the active profile, as a commit is.
  Future<void> setNote(String sha, String text) async {
    // Tidied as git will store it; git hands the old note back already in
    // that form. A note written outside the app with `--no-stripspace` can
    // still hold trailing spaces, and then an unchanged save rewrites it —
    // harmless, and the stored text is the tidy one from then on.
    final next = normalizeNote(text);
    await _noteEdit(
      _l.actSetNote(_short(sha)),
      sha,
      (prev) => next == (prev ?? '') ? null : next,
    );
  }

  /// Removes the note on [sha]; undo writes its text back.
  Future<void> removeNote(String sha) => _noteEdit(
    _l.actRemoveNote(_short(sha)),
    sha,
    (prev) => prev == null ? null : '',
  );

  /// Reads the note on [sha], asks [change] what to write instead (null:
  /// nothing to do; empty: remove it) and writes it, undoably. The lane is
  /// held from the read to the write, so another edit cannot land between
  /// them and leave this one's undo restoring text that is no longer there.
  ///
  /// Undo and redo restore the note's text, written afresh by the active
  /// profile: the original notes commit, with its author and date, is not
  /// brought back.
  Future<void> _noteEdit(
    String label,
    String sha,
    String? Function(String? prev) change,
  ) async {
    if (_blockedByRepoOp) return;
    final busy = _ref.read(busyProvider.notifier);
    busy.state = BusyState(label);
    try {
      final String? prev;
      try {
        prev = await note(sha);
      } on GitException catch (e) {
        _toastErr(label, e);
        return;
      }
      final next = change(prev);
      if (next == null) return;
      final id = _identity;
      Future<void> write(String? text) => text == null || text.isEmpty
          ? _writer.removeNote(sha)
          : _writer.setNote(
              sha,
              text,
              authorName: id.name,
              authorEmail: id.email,
            );
      await _undoable(
        label,
        () => write(next),
        undo: () => write(prev),
        redo: () => write(next),
        // The lane is already ours, taken before the read.
        claimsRepo: false,
      );
    } finally {
      busy.state = null;
    }
  }

  /// Merges [remote]'s notes in, then publishes them. Outside the undo
  /// journal, as any push is. With no notes on either side there is nothing
  /// to send, which is said as such rather than as git's refspec error.
  Future<void> pushNotes(String remote) async {
    final id = _identity;
    var none = false;
    await _network(
      _l.actPushNotes(remote),
      (cancel) async => none = !await _writer.pushNotes(
        remote,
        authorName: id.name,
        authorEmail: id.email,
        cancel: cancel,
      ),
      writesWorkingTree: false,
      toastSuccess: false,
      onSuccess: () => _ref
          .read(toastProvider.notifier)
          .show(
            none
                ? _l.actNoNotesToPush
                : _l.actComplete(_l.actPushNotes(remote)),
            kind: none ? ToastKind.info : ToastKind.success,
          ),
    );
  }

  /// Merges [remote]'s notes into ours. On the repository lane, not the
  /// fetch one: it writes the same notes ref a note edit does. A remote with
  /// no notes is news, not a failure.
  Future<void> fetchNotes(String remote) async {
    final id = _identity;
    var none = false;
    await _network(
      _l.actFetchNotes(remote),
      (cancel) async => none = !await _writer.fetchNotes(
        remote,
        authorName: id.name,
        authorEmail: id.email,
        cancel: cancel,
      ),
      writesWorkingTree: false,
      toastSuccess: false,
      onSuccess: () => _ref
          .read(toastProvider.notifier)
          .show(
            none
                ? _l.actRemoteHasNoNotes(remote)
                : _l.actComplete(_l.actFetchNotes(remote)),
            kind: none ? ToastKind.info : ToastKind.success,
          ),
    );
  }

  Future<void> stashPush([
    StashPushOptions options = const StashPushOptions(),
  ]) async {
    if (_blockedByRepoOp) return;
    // Putting the files back to HEAD runs the LFS filter. No Cancel, though:
    // one stopped after saving but mid-reset leaves a tree the stash then
    // refuses to pop onto, and the objects are local, so it is rarely slow.
    final timeout = await _lfsInPlay('HEAD')
        ? GitWriter.lfsTransferTimeout
        : null;
    try {
      await _timed('Stash push', () => _writer.stashPush(options, timeout));
      _refresh();
    } on GitException catch (e) {
      _toastErr(_l.actStash, e);
    }
  }

  /// Turns stash [ref] into branch [name], made at the commit the stash was
  /// taken on, so it always applies cleanly there.
  Future<void> stashBranch(String name, String ref) async {
    if (_blockedByRepoOp) return;
    try {
      await _timed(
        'Branch $name from $ref',
        () => _writer.stashBranch(name, ref),
      );
      _refresh();
    } on GitException catch (e) {
      // A refused checkout can still have created the branch; show that.
      _refresh();
      _toastErr(_l.actBranchFromStash, e);
    }
  }

  Future<void> stashRename(String ref, String message) async {
    if (_blockedByRepoOp) return;
    try {
      await _timed('Rename $ref', () => _writer.stashRename(ref, message));
      _refresh();
    } on GitException catch (e) {
      _refresh();
      _toastErr(_l.actRenameStash, e);
    }
  }

  /// Brings one file of stash [sha] back into the working tree, leaving the
  /// index and the stash itself alone. Undo takes the change back out.
  Future<void> applyStashFile(
    String sha,
    StashContents contents, {
    required String path,
    String? origPath,
    bool untracked = false,
  }) async {
    if (_blockedByRepoOp) return;
    final label = _l.actApplyFromStash(path);
    final String patch;
    try {
      patch = await GitReader(_git, this.path).stashFilePatch(
        sha,
        contents,
        path: path,
        origPath: origPath,
        untracked: untracked,
      );
    } on GitException catch (e) {
      _toastErr(label, e);
      return;
    }
    await applyStashPatch(patch, label: label);
  }

  /// Lays [patch], taken from a stash, onto the working tree. Undoable.
  Future<void> applyStashPatch(String patch, {String? label}) => _undoable(
    label ?? _l.actApplyHunkFromStash,
    () => _writer.applyToWorktree(patch),
    undo: () => _writer.applyToWorktree(patch, reverse: true),
    redo: () => _writer.applyToWorktree(patch),
  );

  Future<void> stashApply(String ref) async {
    if (_blockedByRepoOp) return;
    try {
      await _timed('Stash apply $ref', () => _writer.stashApply(ref));
      _refresh();
    } on GitException catch (e) {
      await _openStashConflictOrToast(_l.actStashApply, e, dropRef: null);
    }
  }

  Future<void> stashPop(String ref) async {
    if (_blockedByRepoOp) return;
    try {
      await _timed('Stash pop $ref', () => _writer.stashPop(ref));
      _refresh();
    } on GitException catch (e) {
      // A conflicted pop keeps the stash; drop it once the resolution finishes.
      await _openStashConflictOrToast(_l.actStashPop, e, dropRef: ref);
    }
  }

  /// After a failed stash apply/pop, open a resolution session when the failure
  /// left conflicts in the tree; otherwise surface the error toast.
  Future<void> _openStashConflictOrToast(
    String label,
    GitException e, {
    required String? dropRef,
  }) async {
    final conflicts = await _conflictFiles();
    if (conflicts.isEmpty) {
      _toastErr(label, e);
      return;
    }
    _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
      kind: MergeKind.stash,
      branch: _l.actStashedChanges,
      dropStashRef: dropRef,
      files: conflicts,
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
            _l.actDroppedStash,
            action: ToastAction(_l.actUndoButton, () async {
              try {
                await _writer.stashStore(sha);
                _refresh();
              } on GitException catch (e) {
                _toastErr(_l.actRestoreStash, e);
              }
            }),
          );
    } on GitException catch (e) {
      _toastErr(_l.actStashDrop, e);
    }
  }

  // --- Merge ----------------------------------------------------------------

  /// Merges [branch] into the current branch. A clean merge commits and is
  /// undoable; a conflict opens the Merge Tool via [mergeSessionProvider].
  ///
  /// [squash] collapses the other branch's work into a staged change with no
  /// second parent, [noCommit] stages a real merge; both stop before the
  /// commit, so the user makes it. Nothing was committed, so nothing is
  /// recorded for undo. [favor] decides hunks both sides changed instead of
  /// raising a conflict.
  Future<void> merge(
    String branch, {
    bool squash = false,
    bool noCommit = false,
    MergeFavor favor = MergeFavor.none,
  }) async {
    if (_blockedByRepoOp) return;
    final prev = await _headSha();
    final staged = squash || noCommit;
    // The merge commit runs the user's hooks, which can take as long as they
    // like. Only the first run can be cancelled; a redo has no busy bar.
    final cancel = GitCancel();
    _ref.read(busyProvider.notifier).state = BusyState(
      _l.actMerge(branch),
      onCancel: cancel.cancel,
    );
    final id = _identity;
    Future<void> apply({GitCancel? cancel}) => _writer.merge(
      branch,
      noFf: true,
      squash: squash,
      noCommit: noCommit,
      favor: favor,
      authorName: id.name,
      authorEmail: id.email,
      cancel: cancel,
    );
    try {
      await _timed('Merge $branch', () => apply(cancel: cancel));
      if (!staged) {
        _ref
            .read(undoProvider(path).notifier)
            .record(
              UndoEntry(
                _l.actMerge(branch),
                undo: () async {
                  await _undoReset(prev);
                  _refresh();
                },
                redo: () async {
                  await apply();
                  _refresh();
                },
              ),
            );
      }
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show(
            staged ? _l.actMergedStaged(branch) : _l.actMerged(branch),
            kind: ToastKind.success,
          );
    } on GitCancelledException {
      // Killed in a hook, git has staged the merged tree without writing
      // MERGE_HEAD, so it would read as the user's own work. git refused to
      // start with anything staged, so resetting the index drops only the
      // merge's; unrelated edits in the working tree stay. A kill that came
      // after the commit landed moved HEAD, and that merge is kept.
      if (await _headSha() == prev) {
        try {
          await _writer.mergeAbort();
        } on GitException catch (e) {
          _toastErr(_l.actMergeLabel, e);
        }
      }
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show(_l.actCancelled(_l.actMergeLabel), kind: ToastKind.warning);
    } on GitException catch (e) {
      final conflicts = await _conflictFiles();
      if (conflicts.isEmpty) {
        _toastErr(_l.actMergeLabel, e);
        return;
      }
      _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
        branch: branch,
        prevSha: prev,
        kind: MergeKind.merge,
        files: conflicts,
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
  /// Runs [op], a switch to [target] ahead of another op. When LFS is in play
  /// it gets the transfer ceiling and a Cancel on the busy bar, which the op
  /// that follows has not claimed yet. Reports whether it went through. A
  /// cancel is always toasted; a failure only unless [quiet].
  Future<bool> _lfsSwitch(
    String label,
    String target,
    Future<void> Function(Duration? timeout, GitCancel? cancel) op, {
    bool quiet = false,
  }) async {
    final lfs = await _lfsInPlay(target);
    final cancel = lfs ? GitCancel() : null;
    // Never take over a busy bar another op is showing: its own `finally`
    // would otherwise clear this one, or this one clear it.
    final claimed = lfs && _ref.read(busyProvider) == null;
    if (claimed) {
      _ref.read(busyProvider.notifier).state = BusyState(
        label,
        onCancel: cancel!.cancel,
      );
    }
    try {
      await op(lfs ? GitWriter.lfsTransferTimeout : null, cancel);
      // Cancelled after the switch landed: the branch is checked out, but the
      // user still asked for what was to follow not to happen.
      if (cancel?.isCancelled ?? false) {
        _refresh();
        _ref
            .read(toastProvider.notifier)
            .show(
              _l.actCancelled(label),
              description: _l.actSwitchFinished,
              kind: ToastKind.warning,
            );
        return false;
      }
      return true;
    } on GitCancelledException {
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show(_l.actCancelled(label), kind: ToastKind.warning);
      return false;
    } on GitException catch (e) {
      if (!quiet) _toastErr(_l.actCheckoutLabel, e);
      return false;
    } finally {
      if (claimed) _ref.read(busyProvider.notifier).state = null;
    }
  }

  Future<bool> _switchTo(String branch) async {
    final ok = await _lfsSwitch(
      _l.actCheckout(branch),
      branch,
      (timeout, cancel) => _checkoutPuttingBack(
        branch,
        cancel,
        () => _writer.checkout(branch, timeout: timeout, cancel: cancel),
      ),
    );
    if (!ok) return false;
    if (await _headRef() != branch) {
      _ref
          .read(toastProvider.notifier)
          .show(_l.actCouldNotSwitch(branch), kind: ToastKind.warning);
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
    var cancelled = false;
    final ok = await _lfsSwitch(_l.actCheckout(rb.name), rb.name, (
      timeout,
      cancel,
    ) async {
      try {
        await _checkoutPuttingBack(
          rb.name,
          cancel,
          () => _writer.checkoutTracking(
            rb.remote,
            rb.branch,
            timeout: timeout,
            cancel: cancel,
          ),
        );
      } finally {
        // Also set when the cancel came after the switch landed (in the
        // post-checkout hook): that returns normally, and is still a cancel.
        cancelled = cancel?.isCancelled ?? false;
      }
    }, quiet: true);
    // A cancel is the user's answer, not a create that lost a race.
    if (cancelled) return false;
    if (!ok) return _switchTo(rb.branch);
    if (await _headRef() != rb.branch) {
      _ref
          .read(toastProvider.notifier)
          .show(_l.actCouldNotSwitch(rb.branch), kind: ToastKind.warning);
      return false;
    }
    return true;
  }

  /// Every unmerged path as a [ConflictFile]. Binary content, and a path one
  /// side deleted, have no markers to parse — they carry no parts and are
  /// resolved as a whole file instead.
  Future<List<ConflictFile>> _conflictFiles() async => [
    for (final f in await GitReader(_git, path).unmergedFiles())
      await _conflictFileFor(f),
  ];

  Future<ConflictFile> _conflictFileFor(WorkingFile f) async {
    final kind = f.conflict ?? ConflictKind.bothModified;
    // A gitlink has no text in the worktree to read — and reading the
    // directory as a file would fail. It is settled by picking a side.
    if (f.submodule) {
      return ConflictFile(
        path: f.path,
        parts: const [],
        kind: kind,
        submodule: true,
      );
    }
    final file = File('$path/${f.path}');
    // Both sides deleted: nothing is left in the worktree to read.
    if (!await file.exists()) {
      return ConflictFile(path: f.path, parts: const [], kind: kind);
    }
    // Sniff a prefix first: a binary conflict can be a very large file, and
    // it is never parsed as text — its preview reads the index stages, under
    // their own size cap.
    final handle = await file.open();
    final List<int> bytes;
    try {
      if (isBinaryContent(await handle.read(binarySniffBytes))) {
        return ConflictFile(
          path: f.path,
          parts: const [],
          kind: kind,
          binary: true,
        );
      }
      await handle.setPosition(0);
      bytes = await handle.read(await file.length());
    } finally {
      await handle.close();
    }
    return ConflictFile(
      path: f.path,
      kind: kind,
      // Malformed bytes are tolerated: a file that is not quite UTF-8 still
      // has markers worth showing, and the bytes it keeps are the user's.
      parts: parseConflicts(utf8.decode(bytes, allowMalformed: true)),
    );
  }

  /// Runs an interactive rebase of the plan [steps] onto [base]. [updateRefs]
  /// moves every branch stacked on a replayed commit along with it (see
  /// [rebaseStackedBranches]).
  Future<void> rebase(
    String base,
    List<RebaseStep> steps, {
    bool updateRefs = false,
  }) async {
    // Replaying a signed commit without -S would quietly drop its signature.
    // Signing needs a configured key, though, and a rebase that dies on its
    // first commit strands the repository mid-rebase — so an unsignable branch
    // is replayed as-is rather than asked to sign.
    final sign =
        steps.any((s) => s.sign && s.action != RebaseAction.drop) &&
        await _canSign();
    final todo = buildRebaseTodo(
      steps,
      updateRefs: updateRefs ? await rebaseStackedBranches(base) : const {},
    );
    await _runRebase(
      (cancel) => _writer.rebase(
        base,
        todo,
        authorName: _identity.name,
        authorEmail: _identity.email,
        sign: sign,
        cancel: cancel,
      ),
      // A command the user typed can run for as long as it likes, and signing
      // waits on a passphrase prompt per commit; a rebase of unsigned picks
      // alone is quick, and stopping one mid-pick gains nothing.
      cancellable: sign || todoRunsUserExec(todo),
    );
  }

  /// Whether a `%G?` status describes a signed commit. 'N' is the only status
  /// meaning "no signature at all"; every other one (including 'E', key missing
  /// locally) describes a commit that was signed, and replaying it unsigned
  /// would quietly downgrade it.
  static bool _isSigned(String status) => status.isNotEmpty && status != 'N';

  /// Whether any commit in [base]..HEAD carries a signature.
  Future<bool> _rangeIsSigned(String base) async =>
      (await _out(['log', '--format=%G?', '$base..HEAD']))
          .split('\n')
          .any(_isSigned);

  /// Whether this repository can produce a signature: an explicit key, or the
  /// blanket setting that has git pick one for every commit.
  Future<bool> _canSign() async =>
      (await _out(['config', '--get', 'user.signingkey'])).isNotEmpty ||
      // --bool because git accepts '1', 'yes' and 'on' for it too.
      (await _out(['config', '--get', '--bool', 'commit.gpgsign'])) == 'true';

  /// Straight rebase of [source] onto [target] (drag-and-drop rebase).
  Future<void> rebaseOnto(String source, String target) async {
    if (!await _switchTo(source)) return;
    // The range is only known once HEAD is on [source]; see [rebase] for why an
    // unsignable branch is replayed as-is rather than asked to sign.
    final sign = await _rangeIsSigned(target) && await _canSign();
    // A straight rebase replays the range without its merges rather than
    // refusing like an interactive one does, so the branch silently comes out
    // linear. Count them first — afterwards they are gone — and say so.
    final merges = await _mergeCount(target);
    await _runRebase(
      (cancel) => _writer.rebaseOnto(
        target,
        authorName: _identity.name,
        authorEmail: _identity.email,
        sign: sign,
        cancel: cancel,
      ),
      // As for [rebase]: signing waits on a prompt per commit.
      cancellable: sign,
      note: merges == 0 ? null : _l.actMergesFlattened(merges),
    );
  }

  /// Local branches pointing at a commit in [base]..HEAD, by commit sha: the
  /// branches stacked on this one, which a rebase can carry along. A branch
  /// checked out anywhere — this checkout's own included — is left out: git
  /// refuses to move a ref another worktree has checked out, and the current
  /// branch moves anyway.
  /// Empty when this git is too old to move them (see [supportsUpdateRefTodo]).
  Future<Map<String, List<String>>> rebaseStackedBranches(String base) async {
    if (!supportsUpdateRefTodo(await _ref.read(gitVersionProvider.future))) {
      return const {};
    }
    final range = (await _out([
      'rev-list',
      base.isEmpty || base == '--root' ? 'HEAD' : '$base..HEAD',
    ])).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toSet();
    if (range.isEmpty) return const {};
    final held = {
      for (final w in await GitReader(_git, path).worktrees())
        if (w.branch != null) w.branch!,
    };
    final refs = await _out([
      'for-each-ref',
      '--format=%(objectname)%00%(refname:short)',
      'refs/heads',
    ]);
    final out = <String, List<String>>{};
    for (final line in refs.split('\n')) {
      final parts = line.split('\x00');
      if (parts.length != 2) continue;
      final (sha, name) = (parts[0], parts[1]);
      if (!range.contains(sha) || held.contains(name)) continue;
      (out[sha] ??= []).add(name);
    }
    return out;
  }

  /// Why the rebase in progress is stopped when nothing is conflicted: a break,
  /// or a failed exec. Read off git's record of the steps it has run.
  Future<RebaseStop?> _rebaseStop() async {
    final done = await _stateFilePath('rebase-merge/done');
    if (done == null || !File(done).existsSync()) return null;
    return parseRebaseStop(await File(done).readAsString());
  }

  Future<String> _rebaseDone() => _rebaseFile('done');

  /// Puts a pick the rebase was stopped in the middle of back at the head of
  /// its todo list, and drops what git had applied of it, so continuing picks
  /// it again. Without this the rebase is stuck: git staged the pick with
  /// nothing recorded that would commit it, refuses to continue over that,
  /// and a skip would drop the commit. Reports whether there was one.
  ///
  /// The reset touches only the pick's own changes: git will not run a step
  /// over uncommitted work, and untracked files are left alone. A commit git
  /// stopped on itself (a conflict) has its stopped-sha and is not this case.
  Future<bool> _requeueInterruptedPick() async {
    if (!await isRebaseInProgress()) return false;
    if (await _stateFileExists('rebase-merge/stopped-sha')) return false;
    final line = interruptedPick(
      await _rebaseDone(),
      await _rebaseFile('rewritten-list'),
    );
    final todo = await _stateFilePath('rebase-merge/git-rebase-todo');
    if (line == null || todo == null) return false;
    await _writer.resetHard('HEAD');
    final file = File(todo);
    final rest = file.existsSync() ? await file.readAsString() : '';
    await file.writeAsString('$line\n$rest');
    return true;
  }

  /// The rebase state file [name], or empty when there is none.
  Future<String> _rebaseFile(String name) async {
    final f = await _stateFilePath('rebase-merge/$name');
    if (f == null || !File(f).existsSync()) return '';
    return File(f).readAsString();
  }

  /// Pre-fills the commit composer with a fixup for the commit titled
  /// [subject]. Nothing is committed: the user stages the fix and commits it,
  /// and a later autosquash rebase folds it into place.
  void prepareFixup(String subject) {
    _ref.read(composerPrefillProvider(path).notifier).state = fixupSubject(
      subject,
    );
    _ref
        .read(toastProvider.notifier)
        .show(_l.actFixupReady, description: _l.actFixupHint);
  }

  /// Everything git printed for [e], stdout first: an exec's own output lands
  /// on git's stdout, and its errors interleave with git's on stderr.
  static String _output(GitException e) => [
    e.result?.stdout.trim() ?? '',
    e.result?.stderr.trim() ?? '',
  ].where((s) => s.isNotEmpty).join('\n');

  /// Tells the user the rebase is waiting on them, and remembers [prev] so the
  /// rebase stays undoable once it is continued to the end.
  /// [cancelled] when the user stopped the step themselves.
  void _pausedAt(
    RebaseStop stop,
    String prev, {
    String? output,
    bool cancelled = false,
  }) {
    _ref.read(_opBaseProvider(path).notifier).state = prev.isEmpty
        ? null
        : prev;
    _ref.read(rebaseExecOutputProvider(path).notifier).state =
        output == null || output.isEmpty ? null : output;
    _refresh();
    if (cancelled) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actCancelled(_l.actRebase),
            // Only git itself is killed (see GitCancel.cancel): the command it
            // was running can outlive it.
            description: _l.actRebaseStoppedAt(stop.command ?? stop.kind.name),
            kind: ToastKind.warning,
          );
      return;
    }
    _ref
        .read(toastProvider.notifier)
        .show(
          switch (stop.kind) {
            RebaseStopKind.exec => _l.actExecFailed,
            RebaseStopKind.reword => _l.actRewordRejected,
            RebaseStopKind.breakpoint => _l.actRebaseBreak,
          },
          description: switch (stop.kind) {
            RebaseStopKind.exec => _l.actExecFailedHint(stop.command ?? ''),
            RebaseStopKind.reword => _l.actRewordRejectedHint,
            RebaseStopKind.breakpoint => _l.actBreakHint,
          },
          kind: ToastKind.warning,
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

  /// True when a paused rebase actually started running its sequence, so there
  /// is a step to skip or continue and replayed commits to lose.
  ///
  /// Distinguishes a rebase paused partway (git records which step it is on)
  /// from one git refused before executing anything — a todo it would not
  /// parse, say. Both leave the state directory behind, but only the first is
  /// worth handing back to the user; the second has nothing to salvage.
  Future<bool> isRebasePartlyDone() async {
    for (final entry in const [
      // The merge backend counts steps in msgnum; the am backend uses next.
      ('rebase-merge', 'msgnum'),
      ('rebase-apply', 'next'),
    ]) {
      final p = (await _out(['rev-parse', '--git-path', entry.$1])).trim();
      if (p.isEmpty) continue;
      final abs = p.startsWith('/') ? p : '$path/$p';
      final counter = File('$abs/${entry.$2}');
      if (counter.existsSync() &&
          counter.readAsStringSync().trim().isNotEmpty) {
        return true;
      }
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
  Future<bool> rebaseCrossesMerge(String base) async =>
      await _mergeCount(base) > 0;

  /// How many merge commits are in [base]..HEAD, or the whole history when
  /// [base] is empty.
  Future<int> _mergeCount(String base) async =>
      int.tryParse(
        await _out([
          'rev-list',
          '--count',
          '--merges',
          base.isEmpty ? 'HEAD' : '$base..HEAD',
        ]),
      ) ??
      0;

  /// Commits between [base] and HEAD (oldest-first), as an initial pick plan.
  /// Each step records whether its commit was signed, so replaying it can keep
  /// the signature. Asking for `%G?` makes git verify the signed commits in the
  /// range, which is a gpg call each — fine for a rebase range, which is the
  /// handful of commits a branch is ahead by.
  Future<List<RebaseStep>> rebaseStepsFrom(String base) async {
    final out = await _out([
      'log',
      '--reverse',
      '--format=%H%x1f%s%x1f%G?',
      '$base..HEAD',
    ]);
    if (out.isEmpty) return const [];
    final steps = <RebaseStep>[];
    for (final line in out.split('\n')) {
      final parts = line.split('\x1f');
      if (parts.length < 3) continue;
      steps.add(
        RebaseStep(
          parts[0],
          RebaseAction.pick,
          // The sha and the status are fixed width, so a summary that holds
          // the separator itself is the middle rather than a lost field.
          message: parts.sublist(1, parts.length - 1).join('\x1f'),
          sign: _isSigned(parts.last),
        ),
      );
    }
    return steps;
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
  ///
  /// Rewording HEAD runs the commit hooks; a refusal is returned, not
  /// toasted, so the caller can show the hook's output. An older commit's
  /// hooks run inside the rebase, which reports its own stop. [noVerify]
  /// skips the hooks it can for this one attempt, on either path.
  Future<HookRejectedException?> rewordCommit(
    String sha,
    String summary, {
    String description = '',
    bool noVerify = false,
  }) async {
    final toasts = _ref.read(toastProvider.notifier);
    if (summary.trim().isEmpty) {
      toasts.show(_l.actCommitMessageEmpty, kind: ToastKind.warning);
      return null;
    }
    final target = await _out(['rev-parse', sha]);
    final wasSigned = _isSigned(
      await _out(['log', '-1', '--format=%G?', target]),
    );
    if (target == await _headSha()) {
      if (_blockedByRepoOp) return null;
      final prev = target;
      final cancel = GitCancel();
      Future<void> amend({GitCancel? cancel}) => _writer.amendMessage(
        summary,
        description: description,
        sign: wasSigned,
        noVerify: noVerify,
        authorName: _identity.name,
        authorEmail: _identity.email,
        cancel: cancel,
      );
      HookRejectedException? rejection;
      // The tree is unchanged, so soft-resetting to the original commit puts
      // history back exactly as it was and stages nothing extra.
      await _undoable(
        _l.actReword,
        () => amend(cancel: cancel),
        cancel: cancel,
        undo: () => _writer.resetSoft(prev),
        redo: amend,
        handled: (e) {
          if (e is! HookRejectedException) return false;
          rejection = e;
          return true;
        },
      );
      return rejection;
    }
    if (!await _isAncestorOfHead(target)) {
      toasts.show(_l.actNotOnBranch, kind: ToastKind.warning);
      return null;
    }
    // An empty parent means the root commit, which git rebases with `--root`.
    final parent = await _out(['rev-parse', '--verify', '--quiet', '$target^']);
    final range = parent.isEmpty ? 'HEAD' : '$parent..HEAD';
    if (await rebaseCrossesMerge(parent)) {
      toasts.show(
        _l.actCannotEditMessage,
        description: _l.actRewordWouldFlatten,
        kind: ToastKind.warning,
      );
      return null;
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
              noVerify: noVerify,
            )
          else
            RebaseStep(line.trim(), RebaseAction.pick),
    ];
    if (steps.isEmpty) return null;
    await rebase(parent.isEmpty ? '--root' : parent, steps);
    return null;
  }

  Future<bool> _isAncestorOfHead(String sha) async => (await _git.run([
    'merge-base',
    '--is-ancestor',
    sha,
    'HEAD',
  ], repoPath: path)).ok;

  /// Runs [op] as a rebase, with [note] added to the success toast when the
  /// result needs explaining.
  ///
  /// [cancellable] puts Cancel on the busy bar; [op] is handed the handle it
  /// cancels, or null.
  Future<void> _runRebase(
    Future<void> Function(GitCancel? cancel) op, {
    String? note,
    bool cancellable = false,
  }) async {
    if (_blockedByRepoOp) return;
    if (await isRebaseInProgress()) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actRebaseInProgress,
            description: _l.actRebaseFinishFirst,
            kind: ToastKind.warning,
            action: ToastAction(_l.actAbortRebase, () async {
              try {
                await _writer.rebaseAbort();
                _refresh();
              } on GitException catch (e) {
                _toastErr(_l.actAbortRebase, e);
              }
            }),
          );
      return;
    }
    final prev = await _headSha();
    _ref.read(rebaseExecOutputProvider(path).notifier).state = null;
    final cancel = cancellable ? GitCancel() : null;
    _ref.read(busyProvider.notifier).state = BusyState(
      _l.actRebase,
      onCancel: cancel?.cancel,
    );
    try {
      await _timed('Rebase', () => op(cancel));
      // A break stops the sequence without failing it: git exits cleanly with
      // the rebase still open, and calling that finished would record an undo
      // for half a rebase.
      if (await isRebaseInProgress()) {
        _pausedAt(await _rebaseStop() ?? const RebaseStop.breakpoint(), prev);
        return;
      }
      _ref
          .read(undoProvider(path).notifier)
          .record(
            UndoEntry(
              _l.actRebase,
              undo: () async {
                await _undoReset(prev);
                _refresh();
              },
              // Re-run the same rebase op to redo it.
              redo: () async {
                await op(null);
                _refresh();
              },
            ),
          );
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actComplete(_l.actRebase),
            description: note,
            kind: ToastKind.success,
          );
    } on GitException catch (e) {
      final conflicts = await _conflictFiles();
      if (conflicts.isEmpty) {
        // Nothing to resolve, so there is no session to hand the user. A rebase
        // that got partway through its sequence is paused on something they can
        // act on rather than broken — a pick that applied to nothing (its
        // commit already reached the base under another sha) is the common
        // case, and it wants a skip. Leave it and let the working-tree panel
        // offer Continue and Abort; unwinding here would throw away every
        // commit already replayed.
        final stop = await _rebaseStop();
        if (stop != null && stop.failed) {
          _pausedAt(
            stop,
            prev,
            output: _output(e),
            cancelled: e is GitCancelledException,
          );
          return;
        }
        // Stopped mid-pick — cancelled or timed out while signing, say. Put
        // back, the pick waits at the head of the list like any other step.
        final requeued = await _requeueInterruptedPick();
        // A cancel that left nothing to pick again (a squash, or nothing
        // started) undoes the rebase: the branch goes back exactly as it was.
        if (e is GitCancelledException && !requeued) {
          if (await isRebaseInProgress()) await _writer.rebaseAbort();
          _refresh();
          _ref
              .read(toastProvider.notifier)
              .show(
                _l.actCancelled(_l.actRebase),
                description: _l.actRebaseRestored,
                kind: ToastKind.warning,
              );
          return;
        }
        if (requeued || await isRebasePartlyDone()) {
          // Same base the conflict path records, so continuing stays undoable.
          _ref.read(_opBaseProvider(path).notifier).state = prev.isEmpty
              ? null
              : prev;
          _refresh();
          _ref
              .read(toastProvider.notifier)
              .show(
                e is GitCancelledException
                    ? _l.actCancelled(_l.actRebase)
                    : _l.actRebasePaused,
                description: _l.actRebaseNothingToResolve,
                kind: ToastKind.warning,
              );
          return;
        }
        // Refused before it replayed anything (or already unwound): a plain
        // failure. Clear any state directory git left, which would otherwise
        // poison every later rebase.
        if (await isRebaseInProgress()) await _writer.rebaseAbort();
        _toastErr(_l.actRebase, e);
        return;
      }
      _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
        branch: 'rebase',
        prevSha: prev,
        kind: MergeKind.rebase,
        files: conflicts,
      );
      _refresh();
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  /// Writes the resolved files and stages them. Nothing is committed here: the
  /// user reviews the staged result and then commits it (a merge) or continues
  /// the sequence with [continueOp] (a rebase, cherry-pick or revert). A stash
  /// resolution is complete once staged, so its stash is dropped. Call only
  /// when the session reports all conflicts resolved.
  Future<void> resolveConflicts(MergeSession session) async {
    // A merge tool still open on one of the files would stage its own result
    // over this one when it closes.
    if (_blockedByRepoOp) return;
    try {
      await _timed('Resolve conflicts', () => _resolveConflicts(session));
    } on GitException catch (e) {
      _toastErr(_l.actResolveConflicts, e);
    }
  }

  /// Opens the working-tree copy of [relPath] in the user's editor, at [line]
  /// when the command takes one. Completes once the editor process ends; the
  /// UI does not wait on it. Failures surface as toasts.
  Future<void> openInEditor(String relPath, {int line = 1}) async {
    final toasts = _ref.read(toastProvider.notifier);
    final file = p.join(path, relPath);
    if (!File(file).existsSync()) {
      toasts.show(_l.extFileMissing(relPath), kind: ToastKind.warning);
      return;
    }
    final String exe;
    final List<String> args;
    try {
      (exe, args) = editorInvocation(
        _ref.read(settingsProvider).editorCommand,
        file,
        line: line,
        os: Platform.operatingSystem,
      );
    } on FormatException {
      toasts.show(
        _l.extBadCommand,
        description: _l.extBadCommandHint,
        kind: ToastKind.error,
      );
      return;
    }
    try {
      final r = await _ref.read(externalLauncherProvider).run(exe, args);
      // Explorer exits 1 even when it opened the file.
      if (r.exitCode != 0 && exe != 'explorer') {
        final err = r.stderr.toString().trim();
        toasts.show(
          _l.extLaunchFailed(exe),
          description: err.isEmpty ? null : err,
          kind: ToastKind.error,
        );
      }
    } on ProcessException catch (e) {
      toasts.show(
        _l.extLaunchFailed(exe),
        description: e.message,
        kind: ToastKind.error,
      );
    }
  }

  /// The tool git would run for [kind], or null — after saying why — when
  /// there is none Mergelio can start.
  Future<ToolReady?> _externalTool(ToolKind kind) async {
    final toasts = _ref.read(toastProvider.notifier);
    final ExternalToolConfig config;
    try {
      config = await ExternalGitTools(_git, path).config();
    } on GitException catch (e) {
      _toastErr(
        kind == ToolKind.diff ? _l.extOpenInDiffTool : _l.extMergeTool,
        e,
      );
      return null;
    }
    switch (pickExternalTool(config, kind)) {
      case final ToolReady tool:
        return tool;
      case ToolMissing():
        toasts.show(
          kind == ToolKind.diff ? _l.extNoDiffTool : _l.extNoMergeTool,
          description: kind == ToolKind.diff
              ? _l.extNoDiffToolHint
              : _l.extNoMergeToolHint,
          kind: ToastKind.warning,
        );
      case ToolNeedsTerminal(:final name):
        toasts.show(
          _l.extTerminalTool(name),
          description: _l.extTerminalToolHint,
          kind: ToastKind.warning,
        );
    }
    return null;
  }

  /// Shows [target] in git's configured diff tool. Read-only, so it holds no
  /// lane: several can be open while the user keeps working.
  Future<void> openDifftool(DiffTarget target) async {
    final open = openDiffToolsProvider.notifier;
    if (_ref.read(openDiffToolsProvider) >= kMaxOpenDiffTools) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.extTooManyDiffTools(kMaxOpenDiffTools),
            description: _l.extTooManyDiffToolsHint,
            kind: ToastKind.warning,
          );
      return;
    }
    // Counted from before the config read, so a burst of clicks cannot slip
    // past the limit while it is in flight.
    _ref.read(open).state++;
    try {
      await _openDifftool(target);
    } finally {
      _ref.read(open).state--;
    }
  }

  Future<void> _openDifftool(DiffTarget target) async {
    final tool = await _externalTool(ToolKind.diff);
    if (tool == null) return;
    final tools = ExternalGitTools(_git, path);
    try {
      final sha = target.commitSha;
      final args = difftoolArgs(
        path: target.path,
        origPath: target.origPath,
        staged: target.staged,
        gui: tool.gui,
        from: sha == null ? null : target.baseRev ?? await tools.diffBase(sha),
        to: sha,
      );
      final r = await _timed('Diff tool', () => tools.difftool(args));
      if (!r.ok) {
        _ref
            .read(toastProvider.notifier)
            .show(
              _l.extToolFailed(tool.name),
              description: r.err.isEmpty ? null : r.err,
              kind: ToastKind.error,
            );
      }
    } on GitException catch (e) {
      _toastErr(_l.extOpenInDiffTool, e);
    }
  }

  /// Hands the conflicted [relPath] to git's configured merge tool. git
  /// stages the file when the tool reports success; that is as far as this
  /// goes — committing, or continuing the operation, stays with the user.
  ///
  /// Only a file both sides still have can go to the tool; see
  /// [canUseMergeTool].
  ///
  /// Holds the repository lane while the tool is open, since git writes the
  /// file and the index when it closes. A file git staged leaves the merge
  /// session, and the last one to go finishes it the way Resolve does. A
  /// file still conflicted stays in the session as it was.
  Future<void> openMergeTool(String relPath) async {
    if (_blockedByRepoOp) return;
    final toasts = _ref.read(toastProvider.notifier);
    final conflict = _ref
        .read(mergeSessionProvider(path))
        ?.files
        .where((f) => f.path == relPath)
        .firstOrNull;
    if (conflict != null && !canUseMergeTool(conflict)) {
      // git would stop to ask whether to keep or delete the file, and leave
      // its temporary copies behind when nobody answers.
      toasts.show(
        _l.extMergeToolNeedsBoth(relPath),
        description: _l.extMergeToolNeedsBothHint,
        kind: ToastKind.warning,
      );
      return;
    }
    final cancel = GitCancel();
    final label = _l.extMergeTool;
    // Taken before the config read, so a second click cannot start a second
    // tool on the same file.
    _ref.read(busyProvider.notifier).state = BusyState(
      label,
      onCancel: cancel.cancel,
    );
    GitResult? result;
    ToolReady? tool;
    final dir = Directory(p.dirname(p.join(path, relPath)));
    var copiesBefore = const <String>{};
    try {
      tool = await _externalTool(ToolKind.merge);
      if (tool == null) return;
      // Cancelled while the config was read: nothing has opened, so there is
      // nothing to warn about or clean up.
      if (cancel.isCancelled) {
        toasts.show(_l.actCancelled(label), kind: ToastKind.warning);
        tool = null;
        return;
      }
      copiesBefore = _mergetoolCopies(dir, relPath);
      final args = mergetoolArgs(relPath, gui: tool.gui);
      result = await _timed(
        label,
        () => ExternalGitTools(_git, path).mergetool(args, cancel: cancel),
      );
    } on GitCancelledException {
      toasts.show(
        _l.extMergeToolLeftOpen(tool!.name),
        description: _l.extMergeToolLeftOpenHint,
        kind: ToastKind.warning,
      );
    } on GitException catch (e) {
      _toastErr(label, e);
    } finally {
      // git was stopped before it could tidy up after itself: take away the
      // copies it made, and only those — any already there are not ours.
      if (tool != null && result == null) {
        for (final n in _mergetoolCopies(dir, relPath)) {
          if (copiesBefore.contains(n)) continue;
          try {
            File(p.join(dir.path, n)).deleteSync();
          } on FileSystemException {
            // Gone already, or not ours to remove.
          }
        }
      }
      _ref.read(busyProvider.notifier).state = null;
    }
    if (tool == null) return;
    await _afterMergeTool(relPath, tool.name, result);
  }

  /// The names in [dir] that look like `git mergetool`'s copies of [relPath].
  Set<String> _mergetoolCopies(Directory dir, String relPath) {
    try {
      return mergetoolLeftovers(relPath, [
        for (final e in dir.listSync()) p.basename(e.path),
      ]).toSet();
    } on FileSystemException {
      return const {};
    }
  }

  Future<void> _afterMergeTool(
    String relPath,
    String toolName,
    GitResult? result,
  ) async {
    final toasts = _ref.read(toastProvider.notifier);
    try {
      final still = (await GitReader(
        _git,
        path,
      ).unmergedFiles()).any((f) => f.path == relPath);
      // Read after git answers: a choice made in the meantime must survive.
      final session = _ref.read(mergeSessionProvider(path));
      if (session == null) return;
      if (still) {
        // git puts the file back as it was when the tool fails, so the
        // session's reading of it, and any choices made in it, still hold.
        // A cancel or a failed start has already said so.
        if (result != null) {
          toasts.show(
            _l.extStillConflicted(relPath),
            description: result.err.isNotEmpty
                ? result.err
                : _l.extStillConflictedHint,
            kind: ToastKind.warning,
          );
        }
        return;
      }
      final rest = [
        for (final f in session.files)
          if (f.path != relPath) f,
      ];
      if (rest.isEmpty) {
        await _resolveConflicts(session.withFiles(const []));
        return;
      }
      _ref.read(mergeSessionProvider(path).notifier).state = session.withFiles(
        rest,
      );
      toasts.show(
        _l.extResolvedInTool(relPath, toolName),
        kind: ToastKind.success,
      );
    } on GitException catch (e) {
      _toastErr(_l.extMergeTool, e);
    } finally {
      _refresh();
    }
  }

  /// Settles a conflict that has nothing to merge line by line: check out the
  /// chosen side, or drop the path. An unchosen one is left conflicted — the
  /// Resolve button is gated on every file having an answer.
  Future<void> _applyFileChoice(ConflictFile f) async {
    final ours = f.fileChoice == FileResolution.ours;
    switch (f.fileChoice) {
      case FileResolution.ours:
      case FileResolution.theirs:
        if (f.submodule) {
          // Stage 2 is our side of the merge, stage 3 theirs.
          final stages = await GitReader(_git, path).conflictStages(f.path);
          final sha = stages[ours ? 2 : 3];
          if (sha != null) await _writer.setGitlink(f.path, sha);
          return;
        }
        await _writer.checkoutConflictSide(f.path, ours: ours);
        await _writer.stageFile(f.path);
      case FileResolution.delete:
        await _writer.removeConflicted(f.path);
      case null:
        return;
    }
  }

  Future<void> _resolveConflicts(MergeSession session) async {
    for (final f in session.files) {
      if (f.wholeFile) {
        await _applyFileChoice(f);
        continue;
      }
      await File('$path/${f.path}').writeAsString(f.content());
      await _writer.stageFile(f.path);
    }
    // A conflicted `pop` kept its stash around; the staged resolution replaces
    // it, so drop it.
    if (session.dropStashRef != null) {
      await _writer.stashDrop(session.dropStashRef!);
    }
    // Outlives the session: the undo entry recorded when the operation finally
    // finishes still has to reset back to where the operation started.
    _ref.read(_opBaseProvider(path).notifier).state = session.prevSha.isEmpty
        ? null
        : session.prevSha;
    _ref.read(mergeSessionProvider(path).notifier).state = null;
    _refresh();
    _ref
        .read(toastProvider.notifier)
        .show(
          _l.actConflictsResolved,
          description: switch (session.kind) {
            MergeKind.stash => null,
            MergeKind.merge => _l.actReviewThenCommit,
            _ => _l.actReviewThenContinue,
          },
          kind: ToastKind.success,
        );
  }

  /// Finishes the operation whose resolution is already staged by continuing
  /// its sequence. A merge is left alone — it closes with an ordinary commit
  /// from the composer, which is where the user reviews the message.
  Future<void> continueOp() async {
    final pending = await pendingOp();
    if (pending == null || !pending.continues) return;
    if (_blockedByRepoOp) return;
    final label = switch (pending.kind) {
      MergeKind.rebase => _l.actContinueRebase,
      MergeKind.cherryPick => _l.actContinueCherryPick(pending.branch),
      _ => _l.actContinueRevert(pending.branch),
    };
    // A cherry-pick or revert commits through the user's hooks, and a rebase's
    // queued steps may include a command of the user's, or a signature that
    // waits on a passphrase prompt; any of them can run for as long as it
    // likes. git records a signing rebase's flag in gpg_sign_opt.
    final cancel =
        pending.kind != MergeKind.rebase ||
            todoRunsUserExec(await _rebaseFile('git-rebase-todo')) ||
            (await _rebaseFile('gpg_sign_opt')).trim().isNotEmpty
        ? GitCancel()
        : null;
    _ref.read(busyProvider.notifier).state = BusyState(
      label,
      onCancel: cancel?.cancel,
    );
    try {
      await _timed(label, () => _continueOp(pending, cancel));
    } on GitCancelledException {
      _refresh();
      _ref
          .read(toastProvider.notifier)
          .show(_l.actCancelled(label), kind: ToastKind.warning);
    } on GitException catch (e) {
      _toastErr(label, e);
    } finally {
      _ref.read(busyProvider.notifier).state = null;
    }
  }

  Future<void> _continueOp(PendingOp pending, GitCancel? cancel) async {
    final id = _identity;
    // A resolution that matches HEAD leaves nothing to commit. git refuses
    // `--continue` there and wants the paused commit skipped instead. A break
    // or failed exec has no paused commit: nothing staged is normal there, and
    // a skip would hard-reset away whatever the user changed meanwhile.
    final empty =
        pending.stop == null &&
        (await _git.run(['diff', '--cached', '--quiet'], repoPath: path)).ok;
    final doneBefore = pending.kind == MergeKind.rebase
        ? await _rebaseDone()
        : '';
    if (pending.kind == MergeKind.rebase) {
      _ref.read(rebaseExecOutputProvider(path).notifier).state = null;
    }
    try {
      switch (pending.kind) {
        case MergeKind.rebase:
          if (empty) {
            await _writer.rebaseSkip(cancel: cancel);
          } else {
            await _writer.rebaseContinue(
              authorName: id.name,
              authorEmail: id.email,
              cancel: cancel,
            );
          }
        case MergeKind.cherryPick:
          if (empty) {
            await _writer.cherryPickSkip(cancel: cancel);
          } else {
            await _writer.cherryPickContinue(
              authorName: id.name,
              authorEmail: id.email,
              cancel: cancel,
            );
          }
        case MergeKind.revert:
          if (empty) {
            await _writer.revertSkip(cancel: cancel);
          } else {
            await _writer.revertContinue(
              authorName: id.name,
              authorEmail: id.email,
              cancel: cancel,
            );
          }
        case MergeKind.merge:
        case MergeKind.stash:
          return;
      }
    } on GitException catch (e) {
      // git reports stopping on the next conflict as a failure. It is not one:
      // hand the fresh conflicts back to the merge tool. Anything else is.
      if (await _reopenIfStillConflicted(pending)) return;
      // Nor is the next exec failing — but only if git got that far. A
      // refusal to continue at all (a dirty tree) leaves the record as it was.
      if (pending.kind == MergeKind.rebase &&
          await _rebaseDone() != doneBefore) {
        final stop = await _rebaseStop();
        if (stop != null && stop.failed) {
          _pausedAt(
            stop,
            _ref.read(_opBaseProvider(path)) ?? '',
            output: _output(e),
            cancelled: e is GitCancelledException,
          );
          return;
        }
        // Stopped in the middle of a later pick: put it back so the rebase
        // can be continued, then report the stop as it was.
        await _requeueInterruptedPick();
      }
      rethrow;
    }
    if (await _reopenIfStillConflicted(pending)) return;
    // Continued cleanly into the next break.
    if (pending.kind == MergeKind.rebase && await isRebaseInProgress()) {
      _pausedAt(
        await _rebaseStop() ?? const RebaseStop.breakpoint(),
        _ref.read(_opBaseProvider(path)) ?? '',
      );
      return;
    }
    final base = _ref.read(_opBaseProvider(path));
    // Skipping the paused commit of a lone cherry-pick or revert ends the
    // sequence with HEAD where it started — nothing to undo. Skipping one of
    // several does not: the picks either side of it still land. A rebase is a
    // sequence of its own: the steps after the skipped one still replay, so the
    // branch moves either way.
    final moved =
        pending.kind == MergeKind.rebase ||
        (base != null && await _headSha() != base);
    if (base != null && moved) {
      await _recordFinishUndo(base, switch (pending.kind) {
        MergeKind.rebase => _l.actRebase,
        MergeKind.cherryPick => _l.actCherryPick(pending.branch),
        _ => _l.actRevert(pending.branch),
      });
    }
    _ref.read(_opBaseProvider(path).notifier).state = null;
    _refresh();
    _ref.read(toastProvider.notifier).show(switch (pending.kind) {
      MergeKind.rebase => _l.actComplete(_l.actRebase),
      MergeKind.cherryPick => _l.actComplete(_l.actCherryPick(pending.branch)),
      _ => _l.actComplete(_l.actRevert(pending.branch)),
    }, kind: ToastKind.success);
  }

  /// The operation the repository sits in the middle of, or null when it sits
  /// in none. Read from git's own state files rather than from the open
  /// session, so an operation left paused by an earlier run — or started from a
  /// terminal — is found just the same.
  Future<PendingOp?> pendingOp() async {
    // A rebase is asked about first: it replays picks, and some git versions
    // leave CHERRY_PICK_HEAD beside the rebase state while one is conflicted.
    // Continuing the pick rather than the rebase would strand the rebase.
    if (await isRebaseInProgress()) {
      return PendingOp(kind: MergeKind.rebase, stop: await _rebaseStop());
    }
    final seq = await _sequencerKind();
    if (seq != null) {
      return PendingOp(kind: seq, branch: await _sequencerHeadLabel(seq));
    }
    if (await _stateFileExists('MERGE_HEAD')) {
      return PendingOp(
        kind: MergeKind.merge,
        branch: (await _out(['rev-parse', '--short', 'MERGE_HEAD'])).trim(),
      );
    }
    return null;
  }

  /// The bisect this repository is in the middle of, or null when it is in
  /// none. Read from git's own state rather than from anything the app
  /// remembers, so a bisect started in a terminal — or one left running by an
  /// earlier session — reads exactly the same.
  ///
  /// Nothing here parses command output. Git translates its progress messages,
  /// so a regex over "revisions left" would find nothing under a non-English
  /// locale; `for-each-ref` and `--bisect-vars` are stable in every locale.
  /// Throws what it hits. A git call that cannot run raises a
  /// [GitException], but the state files are read straight off disk, so a
  /// file that vanishes between the existence test and the read — or one
  /// that will not decode — raises a [FileSystemException] instead. Every
  /// caller that runs from a button has to be ready for both.
  Future<BisectState?> bisectState() async {
    // BISECT_START is only asked whether it is there: its contents are the
    // branch a reset returns to, which is git's business to remember and
    // nothing here has to know.
    if (!await _stateFileExists('BISECT_START')) return null;

    final termsPath = await _stateFilePath('BISECT_TERMS');
    final terms = parseBisectTerms(
      termsPath != null && File(termsPath).existsSync()
          ? File(termsPath).readAsStringSync()
          : null,
    );

    // Read against the repository's own terms: git names these refs after
    // them, so a repository that renamed its ends holds no ref called good or
    // bad and every mark in it would otherwise read as nothing at all.
    final marks = parseBisectRefs(
      await _out([
        'for-each-ref',
        '--format=%(objectname) %(refname)',
        'refs/bisect',
      ]),
      terms,
    );

    // Only ask for counts once both ends of the range exist; with one end git
    // would walk the whole history to answer.
    final args = bisectVarsArgs(marks);
    final vars = args.isEmpty
        ? const BisectVars()
        : parseBisectVars(await _out(['rev-list', '--bisect-vars', ...args]));

    return BisectState(
      marks: marks,
      terms: terms,
      currentSha: await _headSha(),
      revisionsLeft: vars.nr,
      steps: vars.steps,
      firstBad: firstBadFrom(marks, vars.nr),
    );
  }

  /// True when anything is staged, modified or untracked — a bisect checks
  /// commits out, so it needs a tree it will not clobber.
  Future<bool> _treeIsDirty() async =>
      (await _out(['status', '--porcelain'])).isNotEmpty;

  /// True when tracked files have been changed, ignoring untracked ones.
  ///
  /// This is the question a failed run asks: a command that writes scratch
  /// files of its own leaves git free to check the next commit out, while a
  /// change to a tracked file stops the hunt dead. Counting scratch files here
  /// would tell the user their command modified tracked files when it did not,
  /// and bury the real ending git reported.
  Future<bool> _trackedFilesDirty() async =>
      (await _out(['status', '--porcelain', '--untracked-files=no']))
          .isNotEmpty;

  /// Opens a bisect with [sha] as the first bad commit.
  ///
  /// Refuses on a dirty tree rather than stashing: a stash popped several
  /// steps later, possibly in a later session, is not something to do to
  /// someone's work without being asked.
  Future<void> startBisect(String sha) async {
    if (_blockedByBisectRun) return;
    final id = await _journalBegin(_l.actBisectStartStep);
    try {
      // Inside the try because it is a git call like any other: one that
      // cannot run has to be reported, not thrown out of a button callback
      // nobody awaits, where it disappears without a toast or a journal entry.
      if (await _treeIsDirty()) {
        throw GitException(_l.actBisectDirty);
      }
      await _timed('Bisect start', () async {
        await _writer.bisectStart();
        await _writer.bisectMark(const BisectTerms().bad, sha);
      });
      await _journalDone(id);
    } catch (e) {
      await _journalFail(id);
      _toastErr(_l.actBisect, e);
    }
    _refresh();
  }

  /// Records [kind] against [sha], opening a bisect first when none is running.
  Future<void> markBisect(String sha, BisectKind kind) async {
    // Ahead of the state read below, which is a git call of its own and has
    // nothing useful to say about a hunt another process is moving.
    if (_blockedByBisectRun) return;
    // Reported here rather than allowed to escape: this runs from a button
    // nobody awaits, and a state read that failed is not a repository known
    // to have no bisect — opening one over a hunt already in progress would
    // throw its refs away.
    final BisectState? current;
    try {
      current = await bisectState();
    } catch (e) {
      _toastErr(_l.actBisect, e);
      return;
    }
    if (current == null) {
      if (kind != BisectKind.bad) {
        _ref
            .read(toastProvider.notifier)
            .show(
              _l.actBisect,
              description: _l.actBisectNeedsBad,
              kind: ToastKind.error,
            );
        return;
      }
      return startBisect(sha);
    }
    // Read out here rather than inside the closure below: a local assigned
    // somewhere other than its declaration keeps its promotion in straight
    // line code but loses it inside a closure.
    final terms = current.terms;
    final id = await _journalBegin(_l.actBisectMarkStep(kind.name));
    try {
      await _timed('Bisect ${kind.name}', () async {
        if (kind == BisectKind.skip) {
          await _writer.bisectSkip(rev: sha);
        } else {
          await _writer.bisectMark(bisectCommandFor(kind, terms), sha);
        }
      });
      await _journalDone(id);
    } catch (e) {
      await _journalFail(id);
      _toastErr(_l.actBisect, e);
    }
    _refresh();
  }

  /// Sets the commit under test aside as untestable.
  Future<void> skipBisect() async {
    if (_blockedByBisectRun) return;
    final String? sha;
    try {
      sha = (await bisectState())?.currentSha;
    } catch (e) {
      _toastErr(_l.actBisect, e);
      return;
    }
    if (sha == null) return;
    await markBisect(sha, BisectKind.skip);
  }

  /// Ends the bisect and returns to the branch it started from.
  ///
  /// Refused while a run is in flight, the quit dialog's Reset included. A
  /// reset racing the run leaves the repository half-returned — refs gone from
  /// under a process still writing them, HEAD moved out from under a checkout
  /// — while refusing leaves the hunt exactly where it stands, which the next
  /// launch can still read and reset cleanly.
  Future<void> resetBisect() async {
    if (_blockedByBisectRun) return;
    final id = await _journalBegin(_l.actBisectResetStep);
    try {
      await _timed('Bisect reset', () => _writer.bisectReset());
      await _journalDone(id);
    } catch (e) {
      await _journalFail(id);
      _toastErr(_l.actBisect, e);
    }
    _refresh();
  }

  /// Whether an outcome counts as the run having done its job, for the
  /// journal's purposes.
  ///
  /// Landing on the first bad commit is the obvious one. Exhaustion joins it:
  /// every remaining candidate was skipped, so git stopped because the marks
  /// ran out rather than because anything went wrong.
  static bool _bisectRunSucceeded(BisectRunOutcome outcome) =>
      outcome == BisectRunOutcome.finished ||
      outcome == BisectRunOutcome.exhausted;

  /// Hands the rest of the hunt to [command], which git runs over each
  /// remaining candidate until it lands or gives up.
  ///
  /// Returns the outcome rather than toasting a generic success: a run ends in
  /// several materially different ways and the caller decides what to say.
  /// Null means no run was started at all, so there is nothing to report —
  /// the refusal has already said why.
  ///
  /// Claims the repository's operation lane like every other write here. It
  /// held [busyProvider] without checking it before, which let a second
  /// operation start alongside the run and then clear the run's busy state on
  /// its own way out, leaving the status bar idle over a command still going
  /// and no Cancel left to stop it with.
  Future<BisectRunOutcome?> runBisect(String command) async {
    if (_blockedByRepoOp) return null;
    // Re-asked here rather than trusted from whenever the hunt was opened: a
    // tracked file edited since then makes the run report a false verdict, not
    // merely an awkward message. The command tests the working tree, which
    // carries the edit; git records the answer against the commit it checked
    // out, which does not. The hunt then narrows on evidence about code that
    // is in no commit at all and convicts whichever commit that lands on.
    //
    // Tracked files only, like the failure reading further down: a command's
    // own scratch files never stop git checking the next commit out, so
    // counting them would refuse ordinary work.
    final bool dirty;
    try {
      dirty = await _trackedFilesDirty();
    } catch (e) {
      // Unknown is not clean, and there is no lane or journal entry to unwind
      // because nothing has been claimed yet.
      _toastErr(_l.actBisectRun, e);
      return null;
    }
    if (dirty) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actBisectRun,
            description: _l.actBisectRunDirty,
            kind: ToastKind.error,
          );
      return null;
    }
    final cancel = GitCancel();
    _ref.read(bisectRunProvider(path).notifier).state = command;
    // The status bar renders Cancel from this, so a stalled command can be
    // given up on without a second affordance of our own.
    _ref.read(busyProvider.notifier).state = BusyState(
      _l.actBisectRun,
      onCancel: cancel.cancel,
    );
    final id = await _journalBegin(_l.actBisectRunStep);
    try {
      final r = await _timed(
        'Bisect run',
        () => _writer.bisectRun(command, cancel: cancel),
      );
      final outcome = classifyBisectRun(
        r.exitCode,
        r.err,
        // Only asked on failure: a clean run has nothing to explain, and this
        // costs a subprocess.
        treeDirty: r.ok ? false : await _trackedFilesDirty(),
      );
      // A run git could not carry to an answer left the bisect standing
      // wherever it had reached, which is not an operation that completed.
      // Exhaustion is the one non-zero ending that is no fault: git narrowed
      // as far as the recorded marks allow and said so.
      if (_bisectRunSucceeded(outcome)) {
        await _journalDone(id);
      } else {
        await _journalFail(id);
      }
      // Only the failure nobody could name is reported here. Every other
      // outcome is explained in the bar's own words, and the same complaint
      // in two places at once reads as two separate problems.
      if (outcome == BisectRunOutcome.failed) {
        // Wrapped so the shared handler applies the usual preference for
        // git's own stderr over any message of ours — for an unrecognised
        // failure git's wording is all there is to go on.
        _toastErr(_l.actBisectRun, GitException('git bisect run', r));
      }
      return outcome;
    } on GitCancelledException {
      await _journalFail(id);
      return BisectRunOutcome.cancelled;
    } catch (e) {
      await _journalFail(id);
      _toastErr(_l.actBisectRun, e);
      return BisectRunOutcome.failed;
    } finally {
      _ref.read(bisectRunProvider(path).notifier).state = null;
      _ref.read(busyProvider.notifier).state = null;
      _refresh();
    }
  }

  /// The verdict trail git recorded for the session in progress, or null when
  /// it could not be read.
  ///
  /// Reported here and handed back as null rather than thrown, the way every
  /// other bisect action reports: this runs from a button nobody awaits, so
  /// an escaping failure would be seen by no one. Null is what tells the
  /// caller apart "git had nothing to say" from "git could not be asked" —
  /// an empty string for both would render a failure as a blank panel.
  ///
  /// Reads nothing about the repository's own state, so there is nothing for
  /// the graph to catch up with and no refresh to schedule.
  Future<String?> bisectLog() async {
    final id = await _journalBegin(_l.actBisectLogStep);
    try {
      final log = await _timed('Bisect log', () => _writer.bisectLog());
      await _journalDone(id);
      return log;
    } catch (e) {
      await _journalFail(id);
      _toastErr(_l.actBisect, e);
      return null;
    }
  }

  /// The message git prepared for the merge in progress, for the commit
  /// composer to offer. Empty when no merge is open.
  ///
  /// git appends a commented-out list of the conflicted paths, which it would
  /// strip itself when running the editor. The composer commits with `-m`,
  /// where git strips nothing, so the comments come off here instead.
  Future<String> pendingMergeMessage() async {
    final p = await _stateFilePath('MERGE_MSG');
    if (p == null || !File(p).existsSync()) return '';
    final body = [
      for (final line in File(p).readAsLinesSync())
        if (!line.startsWith('#')) line,
    ].join('\n');
    return body.trim();
  }

  /// A paused sequence can stop again on its next commit: reopen the session on
  /// the fresh conflicts and report that the continue is not done yet.
  Future<bool> _reopenIfStillConflicted(PendingOp pending) async {
    final more = await _conflictFiles();
    if (more.isEmpty) return false;
    _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
      branch: pending.branch,
      kind: pending.kind,
      prevSha: _ref.read(_opBaseProvider(path)) ?? '',
      files: more,
    );
    _refresh();
    return true;
  }

  /// Records the undo/redo entry for a completed merge/rebase: undo resets the
  /// branch back to [prev]; redo fast-forwards to the finished result (which
  /// survives in the reflog).
  Future<void> _recordFinishUndo(String prev, String label) async {
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
  /// the working tree (e.g. a conflicted stash apply, or a cherry-pick left
  /// paused by an earlier run). No-op when a session is active or nothing is
  /// conflicted. Resolving only ever stages; the operation itself is finished
  /// afterwards from the working-tree panel.
  Future<void> openConflictResolution() async {
    if (_ref.read(mergeSessionProvider(path)) != null) return;
    final conflicts = await _conflictFiles();
    if (conflicts.isEmpty) return;
    // No prevSha: the operation was found already in progress, so where it
    // started is not known here and finishing it records no undo entry.
    final pending = await pendingOp();
    _ref.read(mergeSessionProvider(path).notifier).state = MergeSession(
      kind: pending?.kind ?? MergeKind.stash,
      branch: pending?.branch ?? '',
      files: conflicts,
    );
  }

  /// Short sha of the commit a paused sequence stopped on, for the tool header.
  Future<String> _sequencerHeadLabel(MergeKind kind) async {
    final ref = kind == MergeKind.cherryPick
        ? 'CHERRY_PICK_HEAD'
        : 'REVERT_HEAD';
    final r = await _git.run(['rev-parse', '--short', ref], repoPath: path);
    return r.ok ? r.out.trim() : '';
  }

  /// Backs the operation being resolved out. The kind comes from the open
  /// session when there is one, and from git's own state otherwise — by the
  /// time the user reviews a staged resolution the session is already closed.
  Future<void> abortMerge() async {
    // A merge tool still open would stage its result into a tree that is
    // no longer merging once it closes.
    if (_blockedByRepoOp) return;
    final kind =
        _ref.read(mergeSessionProvider(path))?.kind ??
        (await pendingOp())?.kind;
    if (kind == null) {
      _ref.read(mergeSessionProvider(path).notifier).state = null;
      _ref.read(_opBaseProvider(path).notifier).state = null;
      return;
    }
    try {
      await _timed('Abort ${kind.name}', () async {
        switch (kind) {
          case MergeKind.rebase:
            await _writer.rebaseAbort();
          case MergeKind.cherryPick:
            await _writer.cherryPickAbort();
          case MergeKind.revert:
            await _writer.revertAbort();
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
      _toastErr(_l.actAbort, e);
    }
    _ref.read(mergeSessionProvider(path).notifier).state = null;
    _ref.read(_opBaseProvider(path).notifier).state = null;
    _ref.read(rebaseExecOutputProvider(path).notifier).state = null;
    _refresh();
  }

  /// Abbreviates a full sha for labels. Anything else is a ref name (a reset
  /// or move can target a branch), which is left whole.
  static String _short(String sha) =>
      sha.length > 7 && _fullSha.hasMatch(sha) ? sha.substring(0, 7) : sha;
  static final _fullSha = RegExp(r'^[0-9a-f]{40}([0-9a-f]{24})?$');

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
          .show(_l.actComplete(label), kind: ToastKind.success);
      return true;
    } on GitException catch (e) {
      _toastErr(label, e);
      return false;
    } on Object catch (_) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actFailed(label),
            description: _l.actUnexpectedError,
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
    _l.actAddWorktree,
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
          .show(_l.actComplete(_l.actRemoveWorktree), kind: ToastKind.success);
      return null;
    } on GitException catch (e) {
      final err = e.result?.err ?? '';
      return err.isNotEmpty ? err : e.message;
    } on Object catch (_) {
      return _l.actUnexpectedError;
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
      _l.actMoveWorktree,
      () => _writer.moveWorktree(from, to),
    );
    if (ok) _ref.read(workspaceProvider.notifier).retargetTabs(from, to);
    return ok;
  }

  Future<bool> worktreeLock(String at, {String? reason}) => _local(
    _l.actLockWorktree,
    () => _writer.lockWorktree(at, reason: reason),
  );

  Future<bool> worktreeUnlock(String at) =>
      _local(_l.actUnlockWorktree, () => _writer.unlockWorktree(at));

  /// Returns git's report. A dry run changes nothing and is shown to the user
  /// before the real prune.
  Future<String> worktreePrune({bool dryRun = false}) async {
    try {
      return await _timed(
        dryRun ? 'Preview prune' : 'Prune worktrees',
        () => _writer.pruneWorktrees(dryRun: dryRun),
      );
    } on GitException catch (e) {
      _toastErr(_l.actPruneWorktrees, e);
      return '';
    } on Object catch (_) {
      _ref
          .read(toastProvider.notifier)
          .show(
            _l.actFailed(_l.actPruneWorktrees),
            description: _l.actUnexpectedError,
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

/// HEAD before the operation currently being resolved, kept past the merge
/// session so the undo entry recorded when the operation finishes can reset
/// back to it. Null when the operation was found already in progress, which
/// records no undo entry.
final _opBaseProvider = StateProvider.family<String?, String>(
  (ref, path) => null,
);

/// What the exec step a rebase stopped on printed, kept until the rebase is
/// continued or aborted so the user can read why it failed. Null when the
/// rebase is not stopped on a failed exec.
final rebaseExecOutputProvider = StateProvider.family<String?, String>(
  (ref, path) => null,
);

/// A commit message for the composer to take up — set by actions that prepare
/// a commit for the user to make (a fixup, say), cleared by the composer once
/// it has filled itself in.
final composerPrefillProvider = StateProvider.family<String?, String>(
  (ref, path) => null,
);

/// The operation the repository is in the middle of, re-read after every
/// refresh: what the working-tree panel offers to commit or continue.
final pendingOpProvider = FutureProvider.family<PendingOp?, String>((
  ref,
  path,
) {
  ref.watch(repoDataProvider(path));
  return ref.read(repoActionsProvider(path)).pendingOp();
});

/// How a commit attempt ended. [rejection] is set when a hook refused it.
class CommitOutcome {
  final bool committed;
  final HookRejectedException? rejection;
  const CommitOutcome({this.committed = false, this.rejection});
}

final repoActionsProvider = Provider.family<RepoActions, String>((ref, path) {
  final git = InFlightGit(ref.watch(gitServiceProvider));
  final actions = RepoActions(ref, path, GitWriter(git, path), git: git);
  ref.onDispose(actions.dispose);
  return actions;
});
