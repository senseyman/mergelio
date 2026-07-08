import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_journal_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.txt').writeAsString('A\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'A']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'a successful mutation leaves a completed (not interrupted) journal',
    () async {
      final kv = InMemoryKeyValueStore();
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(kv)],
      );
      addTearDown(c.dispose);

      await c.read(repoActionsProvider(dir.path)).createBranch('feature');

      // A fresh journal over the same store sees the op recorded and NOT pending.
      final j = OperationJournal(kv, dir.path);
      await j.load();
      expect(j.interrupted, isEmpty);
      expect(j.records.map((r) => r.label), contains('Create branch feature'));
      expect(j.records.every((r) => r.status != OpStatus.pending), isTrue);
    },
  );
}
