import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/operation_journal.dart';

void main() {
  late InMemoryKeyValueStore kv;
  const ts = '2026-07-08T00:00:00.000';

  setUp(() => kv = InMemoryKeyValueStore());

  test('a completed op is not reported as interrupted on reload', () async {
    final j = OperationJournal(kv, '/repo');
    final id = await j.begin('Merge', ts);
    await j.complete(id);

    final j2 = OperationJournal(kv, '/repo');
    await j2.load();
    expect(j2.interrupted, isEmpty);
  });

  test('an op left pending is reported as interrupted, then cleared', () async {
    // begin() persists a pending marker; we never complete it (simulates crash).
    final j = OperationJournal(kv, '/repo');
    await j.begin('Rebase', ts);

    final j2 = OperationJournal(kv, '/repo');
    await j2.load();
    expect(j2.interrupted.map((r) => r.label), ['Rebase']);

    // Once observed it is marked failed, so a second restart is clean.
    final j3 = OperationJournal(kv, '/repo');
    await j3.load();
    expect(j3.interrupted, isEmpty);
  });

  test('a failed op is not treated as interrupted', () async {
    final j = OperationJournal(kv, '/repo');
    final id = await j.begin('Push', ts);
    await j.fail(id);

    final j2 = OperationJournal(kv, '/repo');
    await j2.load();
    expect(j2.interrupted, isEmpty);
  });

  test('journals are isolated per repo path', () async {
    await OperationJournal(kv, '/a').begin('op-a', ts);
    final b = OperationJournal(kv, '/b');
    await b.load();
    expect(b.interrupted, isEmpty);

    final a = OperationJournal(kv, '/a');
    await a.load();
    expect(a.interrupted.map((r) => r.label), ['op-a']);
  });

  test('history is capped at 40 records', () async {
    final j = OperationJournal(kv, '/repo');
    for (var i = 0; i < 50; i++) {
      final id = await j.begin('op$i', ts);
      await j.complete(id);
    }
    expect(j.records.length, 40);
    // Newest survive; oldest pruned.
    expect(j.records.last.label, 'op49');
    expect(j.records.first.label, 'op10');
  });
}
