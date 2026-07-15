import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/repo_watcher.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')}: ${r.err}');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_watch_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.txt').writeAsString('A\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'first']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'an external commit refreshes the repo view via the disk watcher',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(workspaceProvider.notifier).openRepo(dir.path);
      // Keep the data alive + start the watcher.
      final sub = c.listen(repoDataProvider(dir.path), (_, _) {});
      addTearDown(sub.close);
      c.read(repoWatcherProvider);

      final before = await c.read(repoDataProvider(dir.path).future);
      expect(before.commits.length, 1);

      // Commit from "outside" the app — no RepoActions, no _refresh call.
      await File('${dir.path}/b.txt').writeAsString('B\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'external']);

      // Poll until the watcher's debounced invalidate has landed (~300ms + FS
      // event latency), up to a generous ceiling.
      var count = before.commits.length;
      for (var i = 0; i < 80 && count < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        count = (await c.read(
          repoDataProvider(dir.path).future,
        )).commits.length;
      }
      expect(
        count,
        2,
        reason: 'external commit was not picked up by the watcher',
      );
      expect(
        (await c.read(repoDataProvider(dir.path).future)).commits.first.message,
        'external',
      );
    },
  );
}
