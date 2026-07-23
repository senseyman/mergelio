import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out;

  Future<String> commit(String file, String content, String msg) async {
    await File('${dir.path}/$file').writeAsString(content);
    await g(['add', '.']);
    await g(['commit', '-q', '-m', msg]);
    return out(['rev-parse', 'HEAD']);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_rflow_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a clean rebase reorders history and is undoable', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('base.txt', 'base\n', 'base');
    final c1 = await commit('f1.txt', '1\n', 'C1');
    final c2 = await commit('f2.txt', '2\n', 'C2');

    await actions.rebase(base, [
      RebaseStep(c2, RebaseAction.pick),
      RebaseStep(c1, RebaseAction.pick),
    ]);

    expect((await out(['log', '--format=%s'])).split('\n'), [
      'C1',
      'C2',
      'base',
    ]);
    expect(c.read(mergeSessionProvider(dir.path)), isNull);

    // Undoable back to the original order.
    await actions.undo();
    expect((await out(['log', '--format=%s'])).split('\n'), [
      'C2',
      'C1',
      'base',
    ]);
  });

  test(
    'a conflicting rebase opens the tool in rebase mode; finish continues',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      // base → A (edits x) → B (edits x again). Reorder B before A conflicts.
      final base = await commit('x.txt', 'base\n', 'base');
      final a = await commit('x.txt', 'A\n', 'A');
      final b = await commit('x.txt', 'B\n', 'B');

      await actions.rebase(base, [
        RebaseStep(b, RebaseAction.pick),
        RebaseStep(a, RebaseAction.pick),
      ]);

      expect(c.read(mergeSessionProvider(dir.path))?.kind, MergeKind.rebase);

      // Resolve each conflict round to "theirs" until the rebase completes
      // (reordered picks conflict twice here).
      var guard = 0;
      while (c.read(mergeSessionProvider(dir.path)) != null && guard++ < 5) {
        var session = c.read(mergeSessionProvider(dir.path))!;
        for (var i = 0; i < session.files.length; i++) {
          var file = session.files[i];
          for (final h in file.hunkIndices) {
            file = file.withResolution(h, Resolution.theirs);
          }
          session = session.replaceFile(i, file);
        }
        await actions.finishMerge(session);
      }

      // Rebase completed: session cleared and no rebase is in progress.
      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(Directory('${dir.path}/.git/rebase-merge').existsSync(), isFalse);
    },
  );
}
