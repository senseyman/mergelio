import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/concurrency.dart';
import '../domain/git/dashboard.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/git_service.dart';
import '../domain/git/git_writer.dart';
import 'feedback.dart';
import 'lfs.dart';
import 'operation_journal.dart';
import 'repo_actions.dart';
import 'repo_data.dart';
import 'workspace.dart';

/// How many repositories the dashboard reads, fetches or pulls at once. A
/// group of thirty must not start thirty fetches, and the shared git gate is
/// sized for one repository's reads, not a fleet's.
const kDashboardParallelism = 4;

/// Bumped to make one dashboard row read its repository again. Dropped with
/// the row: a dashboard opened afresh reads fresh anyway.
final dashboardRowGenerationProvider = StateProvider.autoDispose
    .family<int, String>((ref, path) => 0);

/// Shared by every row, so opening the dashboard over a large group reads a
/// few repositories at a time rather than all of them at once. One per
/// container, so independent containers never wait on each other's reads.
final dashboardSnapshotGateProvider = Provider<ConcurrencyGate>(
  (ref) => ConcurrencyGate(kDashboardParallelism),
);

/// One dashboard row's state. Disposed with the dashboard, so opening it again
/// always reads fresh.
final repoSnapshotProvider = FutureProvider.autoDispose
    .family<RepoSnapshot, String>((ref, path) {
      ref.watch(dashboardRowGenerationProvider(path));
      final git = ref.watch(gitServiceProvider);
      final gate = ref.watch(dashboardSnapshotGateProvider);
      return gate.run(() => GitReader(git, path).snapshot());
    });

enum DashboardBatchKind { fetch, pull }

enum RowRunState { queued, running, done, failed, skipped, cancelled }

/// Where one repository stands in a batch.
class RowRun {
  final RowRunState state;

  /// Why a pull left the repository out.
  final PullSkip? pullSkip;

  /// A fetch left it out because it has no remote.
  final bool noRemote;

  /// Git's own words for a failure.
  final String? message;

  const RowRun(
    this.state, {
    this.pullSkip,
    this.noRemote = false,
    this.message,
  });

  bool get finished =>
      state != RowRunState.queued && state != RowRunState.running;
}

/// A fetch or pull over a set of repositories, in the order they were given.
class DashboardBatch {
  final DashboardBatchKind kind;
  final Map<String, RowRun> rows;

  const DashboardBatch(this.kind, this.rows);

  int get total => rows.length;
  int get finished => rows.values.where((r) => r.finished).length;
  bool get running => finished < total;

  int count(RowRunState s) => rows.values.where((r) => r.state == s).length;

  DashboardBatch withRow(String path, RowRun run) =>
      DashboardBatch(kind, {...rows, path: run});
}

/// Runs fetch-all and the bulk fast-forward pull over the dashboard's
/// repositories, holding the same lanes single-repository operations use so
/// neither can overlap them.
class DashboardBatchController extends StateNotifier<DashboardBatch?> {
  final Ref _ref;
  GitCancel? _cancel;

  DashboardBatchController(this._ref) : super(null) {
    // Results describe the moment the batch ran and go stale after: a skip
    // for uncommitted changes outlives the commit that fixed it. They are
    // read on the dashboard and cleared when the user leaves it — or
    // switches group, whose rows never ran. A running batch keeps its rows
    // until it ends, so one left running is still there to read on return.
    _ref.listen(
      workspaceProvider.select((w) => (w.dashboard, w.activeGroupId)),
      (prev, next) {
        final left = (prev?.$1 ?? false) && !next.$1;
        if (left || prev?.$2 != next.$2) _clearFinished();
      },
    );
  }

  /// Fetches every repository in [paths] that has a remote. Holds the fetch
  /// lane for the whole batch: auto-fetch and a manual fetch wait it out.
  /// Returns the finished batch, or null when it could not start because
  /// another batch or the lane's own operation is running.
  Future<DashboardBatch?> fetchAll(
    List<String> paths, {
    required String label,
  }) => _runBatch(
    DashboardBatchKind.fetch,
    paths,
    label: label,
    slot: fetchBusyProvider,
    busy: (onCancel) =>
        BusyState.network(label, progress: 0, onCancel: onCancel),
    each: (git, path, cancel) async {
      if ((await GitReader(git, path).remotes()).isEmpty) {
        return const RowRun(RowRunState.skipped, noRemote: true);
      }
      return _journaled(
        path,
        'Fetch',
        () => GitWriter(git, path).fetch(cancel: cancel),
      );
    },
  );

  /// Fast-forwards every repository in [paths] that can be: each is read
  /// afresh right before its pull — the row on screen may be minutes old —
  /// and skipped with the reason when it no longer qualifies. Holds the
  /// repository lane, since a pull rewrites the working tree.
  Future<DashboardBatch?> pullAll(
    List<String> paths, {
    required String label,
  }) => _runBatch(
    DashboardBatchKind.pull,
    paths,
    label: label,
    slot: busyProvider,
    busy: (onCancel) => BusyState(label, progress: 0, onCancel: onCancel),
    each: (git, path, cancel) async {
      RepoSnapshot? snap;
      try {
        snap = await GitReader(git, path).snapshot();
      } on GitException {
        snap = null;
      }
      final skip = pullSkipReason(snap);
      if (skip != null) return RowRun(RowRunState.skipped, pullSkip: skip);
      return _journaled(
        path,
        'Pull',
        () => GitWriter(git, path).pullFastForward(cancel: cancel),
      );
    },
  );

  /// Abandons the running batch: running git is killed, queued rows never
  /// start.
  void cancel() => _cancel?.cancel();

  void _clearFinished() {
    if (state?.running ?? false) return;
    state = null;
  }

  Future<DashboardBatch?> _runBatch(
    DashboardBatchKind kind,
    List<String> paths, {
    required String label,
    required StateProvider<BusyState?> slot,
    required BusyState Function(void Function() onCancel) busy,
    required Future<RowRun> Function(GitService git, String path, GitCancel c)
    each,
  }) async {
    // Refused without a word: the caller tells the user, in their language.
    if ((state?.running ?? false) || _ref.read(slot) != null) return null;
    final cancel = _cancel = GitCancel();
    final git = _ref.read(gitServiceProvider);
    state = DashboardBatch(kind, {
      for (final p in paths) p: const RowRun(RowRunState.queued),
    });
    final initial = busy(cancel.cancel);
    _ref.read(slot.notifier).state = initial;

    void progress() {
      final b = state;
      if (b == null || b.total == 0) return;
      final p = b.finished / b.total;
      _ref.read(slot.notifier).state = initial.touchesWorkingTree
          ? BusyState(label, progress: p, onCancel: cancel.cancel)
          : BusyState.network(label, progress: p, onCancel: cancel.cancel);
    }

    void set(String path, RowRun run) {
      if (!mounted) return;
      state = state?.withRow(path, run);
      if (run.finished) progress();
    }

    final gate = ConcurrencyGate(kDashboardParallelism);
    try {
      await Future.wait([
        for (final path in paths)
          gate.run(() async {
            if (cancel.isCancelled) {
              set(path, const RowRun(RowRunState.cancelled));
              return;
            }
            set(path, const RowRun(RowRunState.running));
            RowRun out;
            try {
              out = await each(git, path, cancel);
            } on GitCancelledException {
              out = const RowRun(RowRunState.cancelled);
            } on GitException catch (e) {
              final err = e.result?.err ?? '';
              out = RowRun(
                RowRunState.failed,
                message: err.isNotEmpty ? err : e.message,
              );
            } on Object {
              out = const RowRun(RowRunState.failed);
            }
            // A cancel that landed while the row was settling still means the
            // user gave up on it, whether git failed under the kill or the row
            // was about to be skipped; one that finished keeps its result.
            if (cancel.isCancelled &&
                (out.state == RowRunState.failed ||
                    out.state == RowRunState.skipped)) {
              out = const RowRun(RowRunState.cancelled);
            }
            // The container went while git ran (the app is closing): nothing
            // is left to show the row on, or to refresh.
            if (!mounted) return;
            set(path, out);
            // A cancelled row is read again too: a git killed part-way can
            // leave the repository changed, e.g. a pull stopped mid-merge.
            if (out.state == RowRunState.done ||
                out.state == RowRunState.failed ||
                out.state == RowRunState.cancelled) {
              _ref.read(dashboardRowGenerationProvider(path).notifier).state++;
              // Only a repository whose graph is already loaded is reloaded:
              // asking for it would load the graph of every repository in the
              // group and keep each one in memory.
              if (_ref.exists(repoDataProvider(path))) {
                _ref.read(repoActionsProvider(path)).refresh();
              }
            }
            // A pull can bring LFS pointers in; their state is read apart
            // from git status.
            if (kind == DashboardBatchKind.pull &&
                (out.state == RowRunState.done ||
                    out.state == RowRunState.cancelled)) {
              _ref.read(lfsGenerationProvider(path).notifier).state++;
            }
          }),
      ]);
    } finally {
      // Torn down mid-batch, the lane went with the container.
      if (mounted) _ref.read(slot.notifier).state = null;
      if (identical(_cancel, cancel)) _cancel = null;
    }
    return mounted ? state : null;
  }

  /// Runs [op] under a journal record for [path], so a crash mid-batch is
  /// reported for that repository on the next launch. Journaling is
  /// best-effort and never fails the operation.
  Future<RowRun> _journaled(
    String path,
    String label,
    Future<void> Function() op,
  ) async {
    final journal = _ref.read(operationJournalProvider(path));
    int? id;
    try {
      id = await journal.begin(label, DateTime.now().toIso8601String());
    } on Object {
      id = null;
    }
    Future<void> mark(Future<void> Function(int) f) async {
      if (id == null) return;
      try {
        await f(id);
      } on Object {
        /* ignore */
      }
    }

    try {
      await op();
    } on Object {
      await mark(journal.fail);
      rethrow;
    }
    await mark(journal.complete);
    return const RowRun(RowRunState.done);
  }
}

final dashboardBatchProvider =
    StateNotifierProvider<DashboardBatchController, DashboardBatch?>(
      (ref) => DashboardBatchController(ref),
    );
