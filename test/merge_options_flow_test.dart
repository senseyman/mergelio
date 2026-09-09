import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

/// Merge options as the action layer applies them: what lands in the tree,
/// and whether an undo entry is recorded for it.
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_mopt_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.txt').writeAsString('base\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    await g(['checkout', '-q', '-b', 'feature']);
    await File('${dir.path}/a.txt').writeAsString('feature\n');
    await File('${dir.path}/b.txt').writeAsString('from feature\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'feature']);

    await g(['checkout', '-q', 'main']);
    await File('${dir.path}/a.txt').writeAsString('main\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'main']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a squash merge stages the work and commits nothing', () async {
    await g(['checkout', '-q', '-b', 'other', 'main']);
    await File('${dir.path}/c.txt').writeAsString('from other\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'add c']);
    await g(['checkout', '-q', 'main']);
    final before = await out(['rev-parse', 'HEAD']);

    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(repoActionsProvider(dir.path)).merge('other', squash: true);

    expect(await out(['rev-parse', 'HEAD']), before);
    expect(await out(['diff', '--cached', '--name-only']), 'c.txt');
    // Nothing was committed, so there is nothing to undo: the user still owns
    // the decision to keep or discard the staged merge.
    expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
    expect(c.read(mergeSessionProvider(dir.path)), isNull);
  });

  test(
    'a no-commit merge stages a real merge for the user to commit',
    () async {
      await g(['checkout', '-q', '-b', 'other', 'main']);
      await File('${dir.path}/c.txt').writeAsString('from other\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'add c']);
      await g(['checkout', '-q', 'main']);
      final before = await out(['rev-parse', 'HEAD']);

      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c
          .read(repoActionsProvider(dir.path))
          .merge('other', noCommit: true);

      expect(await out(['rev-parse', 'HEAD']), before);
      expect(File('${dir.path}/.git/MERGE_HEAD').existsSync(), isTrue);
      expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
    },
  );

  test('favouring theirs commits without opening a merge session', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c
        .read(repoActionsProvider(dir.path))
        .merge('feature', favor: MergeFavor.theirs);

    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(await File('${dir.path}/a.txt').readAsString(), 'feature\n');
    // A committing merge stays undoable.
    expect(c.read(undoProvider(dir.path)).canUndo, isTrue);
    expect(
      (await svc.run(['rev-parse', 'HEAD^2'], repoPath: dir.path)).ok,
      isTrue,
    );
  });

  test('undoing a favoured merge puts HEAD back', () async {
    final before = await out(['rev-parse', 'HEAD']);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await actions.merge('feature', favor: MergeFavor.ours);

    await actions.undo();

    expect(await out(['rev-parse', 'HEAD']), before);
    expect(await File('${dir.path}/a.txt').readAsString(), 'main\n');
  });

  test(
    'a conflicting squash merge opens a session that can be aborted',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      await actions.merge('feature', squash: true);

      expect(
        c.read(mergeSessionProvider(dir.path))?.files.single.path,
        'a.txt',
      );

      await actions.abortMerge();

      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(await File('${dir.path}/a.txt').readAsString(), 'main\n');
    },
  );
}
