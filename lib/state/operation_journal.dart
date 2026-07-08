import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kv_store.dart';

/// Lifecycle of a journaled operation.
enum OpStatus { pending, done, failed }

/// One journaled mutating operation. Persisted so that, after a crash, an op
/// still marked [OpStatus.pending] on the next launch is known to have been
/// interrupted (it never reached complete/fail).
class OpRecord {
  final int id;
  final String label;
  final OpStatus status;
  final String startedAt; // ISO-8601

  const OpRecord({
    required this.id,
    required this.label,
    required this.status,
    required this.startedAt,
  });

  OpRecord copyWith({OpStatus? status}) => OpRecord(
    id: id,
    label: label,
    status: status ?? this.status,
    startedAt: startedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'status': status.name,
    'startedAt': startedAt,
  };

  factory OpRecord.fromJson(Map<String, dynamic> j) => OpRecord(
    id: j['id'] as int,
    label: j['label'] as String,
    status: OpStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => OpStatus.pending,
    ),
    startedAt: j['startedAt'] as String? ?? '',
  );
}

/// A crash-safe, persisted write-ahead log of mutating git operations for one
/// repository. Each op is recorded [begin] (pending) → [complete]/[fail]. If the
/// process dies between those, the record stays pending on disk and is reported
/// via [interrupted] on the next [load], so the user can be warned that a git
/// operation may not have finished cleanly.
class OperationJournal {
  final KeyValueStore _store;
  final String repoPath;

  /// Keep the journal bounded — only recent history is useful.
  static const _cap = 40;

  List<OpRecord> _records = [];
  List<OpRecord> _interrupted = const [];
  int _nextId = 1;
  bool _loaded = false;

  OperationJournal(this._store, this.repoPath);

  String get _key => 'opJournal:$repoPath';

  /// Ops that were still pending when the journal was last loaded — i.e. the app
  /// stopped before they completed. Empty on a clean restart.
  List<OpRecord> get interrupted => _interrupted;

  List<OpRecord> get records => List.unmodifiable(_records);

  /// Loads persisted records and detects interruptions. Any record left pending
  /// is captured into [interrupted] and then marked failed (it will not be
  /// treated as in-flight again).
  Future<void> load() async {
    final raw = await _store.get(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _records = [
        for (final e in list) OpRecord.fromJson(e as Map<String, dynamic>),
      ];
    }
    _interrupted = [
      for (final r in _records)
        if (r.status == OpStatus.pending) r,
    ];
    if (_interrupted.isNotEmpty) {
      _records = [
        for (final r in _records)
          r.status == OpStatus.pending
              ? r.copyWith(status: OpStatus.failed)
              : r,
      ];
      await _persist();
    }
    _nextId = _records.fold(0, (m, r) => r.id > m ? r.id : m) + 1;
    _loaded = true;
  }

  /// Records the start of [label] and returns its id. Persists before the op
  /// runs so a crash mid-op leaves a durable pending marker.
  Future<int> begin(String label, String startedAt) async {
    if (!_loaded) await load();
    final id = _nextId++;
    _records = [
      ..._records,
      OpRecord(
        id: id,
        label: label,
        status: OpStatus.pending,
        startedAt: startedAt,
      ),
    ];
    if (_records.length > _cap) {
      _records = _records.sublist(_records.length - _cap);
    }
    await _persist();
    return id;
  }

  Future<void> complete(int id) => _mark(id, OpStatus.done);
  Future<void> fail(int id) => _mark(id, OpStatus.failed);

  Future<void> _mark(int id, OpStatus status) async {
    _records = [
      for (final r in _records) r.id == id ? r.copyWith(status: status) : r,
    ];
    await _persist();
  }

  Future<void> _persist() =>
      _store.put(_key, jsonEncode([for (final r in _records) r.toJson()]));
}

/// The app's key-value store. Defaults to an in-memory store (used by tests);
/// `main()` overrides it with the Drift-backed store.
final kvStoreProvider = Provider<KeyValueStore>(
  (ref) => InMemoryKeyValueStore(),
);

/// One journal per repository path.
final operationJournalProvider = Provider.family<OperationJournal, String>(
  (ref, path) => OperationJournal(ref.watch(kvStoreProvider), path),
);

/// Interrupted-op notices (`<repo>: <label>`) discovered at startup. Overridden
/// in `main()` after scanning restored repos' journals.
final interruptedOpsProvider = Provider<List<String>>((ref) => const []);
