import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kv_store.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_service.dart';
import '../domain/git/maintenance.dart';
import 'operation_journal.dart';
import 'repo_data.dart';
import 'worktrees.dart';

/// The clock branch ages and scan times are read from. Tests pin it.
final maintenanceClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

MaintenanceReader _reader(Ref ref, String path) =>
    MaintenanceReader(ref.watch(gitServiceProvider), path);

/// What the repository's storage is made of, on disk and as git counts it.
class MaintenanceSize {
  final String gitDir;
  final GitDirSize disk;
  final CountObjects counts;

  const MaintenanceSize({
    required this.gitDir,
    required this.disk,
    required this.counts,
  });
}

final maintenanceSizeProvider = FutureProvider.autoDispose
    .family<MaintenanceSize, String>((ref, path) async {
      final reader = _reader(ref, path);
      final gitDir = await reader.commonGitDir();
      final (disk, counts) = await (
        measureGitDirOffThread(gitDir),
        reader.countObjects(),
      ).wait;
      return MaintenanceSize(gitDir: gitDir, disk: disk, counts: counts);
    });

/// A digest of the refs as the repository data last read them: local branches
/// with their tips, upstreams and which one is checked out, remote-tracking
/// branches and tags. Null until the first read lands.
///
/// It changes when a ref moves — a delete, an undo putting one back, a fetch,
/// a commit, anything done outside the app — and not on the status ticks in
/// between, so it is what the panel's slower reads follow.
final maintenanceRefsKeyProvider = Provider.autoDispose.family<String?, String>(
  (ref, path) => ref.watch(
    repoDataProvider(path).select((d) {
      final data = d.valueOrNull;
      if (data == null) return null;
      return [
        for (final b in data.branches)
          'h ${b.name} ${b.tip} ${b.upstream}${b.current ? ' *' : ''}',
        for (final r in data.remoteBranches)
          'r ${r.remote}/${r.branch} ${r.tip}',
        for (final t in data.tags) 't $t',
      ].join('\n');
    }),
  ),
);

/// Merged and stale branches. Re-read when the refs move rather than on every
/// status tick: a few git calls each time, and only a ref change can alter the
/// answer.
final branchHygieneProvider = FutureProvider.autoDispose
    .family<BranchHygiene, String>((ref, path) async {
      ref.watch(maintenanceRefsKeyProvider(path));
      final held = ref.watch(worktreeByBranchProvider(path));
      return _reader(ref, path).branchHygiene(
        now: ref.read(maintenanceClockProvider)(),
        heldBy: {for (final e in held.entries) e.key: e.value.path},
      );
    });

/// Reflog entries the next gc would expire.
final reflogExpiryProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, path) => _reader(ref, path).reflogExpiryCount(),
);

/// Where the largest-blobs scan stands for one repository.
class BlobScanState {
  /// The latest finished scan, from this session or the cache.
  final BlobScan? result;

  /// Refs have moved since [result] was taken.
  final bool stale;
  final bool scanning;

  /// Why the last scan failed, if it did.
  final String? error;

  const BlobScanState({
    this.result,
    this.stale = false,
    this.scanning = false,
    this.error,
  });
}

/// Runs the largest-blobs scan and keeps its result. The scan walks every
/// object in the repository, so it only ever runs when asked and its result
/// is cached across sessions; a cached one is shown straight away and flagged
/// when the refs no longer match it.
class BlobScanController extends StateNotifier<BlobScanState> {
  final MaintenanceReader _reader;
  final KeyValueStore _store;
  final String _path;
  final DateTime Function() _now;
  GitCancel? _cancel;

  /// How many blobs a scan keeps.
  static const top = 25;

  BlobScanController(this._reader, this._store, this._path, this._now)
    : super(const BlobScanState()) {
    _load();
  }

  String get _key => 'maintenance:blobs:$_path';

  Future<void> _load() async {
    final BlobScan cached;
    try {
      final raw = await _store.get(_key);
      if (raw == null) return;
      cached = BlobScan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return; // an unreadable cache is as good as none
    }
    // A scan started meanwhile is newer than anything on disk.
    if (!mounted || state.scanning || state.result != null) return;
    state = BlobScanState(result: cached);
    await recheck();
  }

  /// Compares the shown result with the refs as they are now.
  Future<void> recheck() async {
    final result = state.result;
    if (result == null || state.scanning) return;
    final String now;
    try {
      now = await _reader.currentRefsFingerprint();
    } on Object {
      return;
    }
    if (!mounted || !identical(state.result, result) || state.scanning) return;
    state = BlobScanState(
      result: result,
      stale: now != result.fingerprint,
      error: state.error,
    );
  }

  Future<void> scan() async {
    if (state.scanning) return;
    final cancel = _cancel = GitCancel();
    final before = state;
    state = BlobScanState(
      result: before.result,
      stale: before.stale,
      scanning: true,
    );
    try {
      final result = await _reader.scanBlobs(
        top: top,
        now: _now(),
        cancel: cancel,
      );
      try {
        await _store.put(_key, jsonEncode(result.toJson()));
      } on Object {
        // Caching is a convenience; the result is still good to show.
      }
      if (mounted) state = BlobScanState(result: result);
    } on GitCancelledException {
      if (mounted) {
        state = BlobScanState(result: before.result, stale: before.stale);
      }
    } on GitException catch (e) {
      final err = e.result?.err ?? '';
      if (mounted) {
        state = BlobScanState(
          result: before.result,
          stale: before.stale,
          error: err.isNotEmpty ? err : e.message,
        );
      }
    } on Object catch (e) {
      if (mounted) {
        state = BlobScanState(
          result: before.result,
          stale: before.stale,
          error: '$e',
        );
      }
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  void cancel() => _cancel?.cancel();

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }
}

/// Kept alive, not auto-disposed: a scan the user started keeps running, and
/// its result stays, after the panel that started it is closed.
final blobScanProvider =
    StateNotifierProvider.family<BlobScanController, BlobScanState, String>(
      (ref, path) => BlobScanController(
        MaintenanceReader(ref.watch(gitServiceProvider), path),
        ref.watch(kvStoreProvider),
        path,
        ref.read(maintenanceClockProvider),
      ),
    );
