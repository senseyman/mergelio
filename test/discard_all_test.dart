import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

/// Discarding every uncommitted change at once: tracked work always, untracked
/// files only when asked, and all of it undoable as a single action.
void main() {
  late Directory repo;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: repo.path)).stdout.trim();

  File file(String name) => File('${repo.path}/$name');

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_discardall_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await file('kept.txt').writeAsString('committed\n');
    await file('staged.txt').writeAsString('committed\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    // One unstaged change, one staged change, one untracked file.
    await file('kept.txt').writeAsString('unstaged edit\n');
    await file('staged.txt').writeAsString('staged edit\n');
    await g(['add', 'staged.txt']);
    await file('new.txt').writeAsString('brand new\n');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test(
    'tracked changes are reverted, untracked files are left alone',
    () async {
      final c = container();

      await c.read(repoActionsProvider(repo.path)).discardAll();

      expect(await file('kept.txt').readAsString(), 'committed\n');
      expect(await file('staged.txt').readAsString(), 'committed\n');
      expect(await out(['status', '--porcelain']), '?? new.txt');
      expect(await file('new.txt').readAsString(), 'brand new\n');
    },
  );

  test('untracked files are deleted when asked for', () async {
    final c = container();

    await c
        .read(repoActionsProvider(repo.path))
        .discardAll(includeUntracked: true);

    expect(await file('new.txt').exists(), isFalse);
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test('undo restores the working tree and what was staged', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(repo.path));

    await actions.discardAll(includeUntracked: true);
    await actions.undo();

    expect(await file('kept.txt').readAsString(), 'unstaged edit\n');
    expect(await file('staged.txt').readAsString(), 'staged edit\n');
    expect(await file('new.txt').readAsString(), 'brand new\n');
    // staged.txt was staged before the discard and must be staged again.
    expect(await out(['diff', '--cached', '--name-only']), 'staged.txt');
  });

  test('the whole sweep is a single undo entry', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(repo.path));

    await actions.discardAll(includeUntracked: true);
    expect(c.read(undoProvider(repo.path)).past.length, 1);

    await actions.undo();
    expect(c.read(undoProvider(repo.path)).canUndo, isFalse);
  });

  test('redo discards again after an undo', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(repo.path));

    await actions.discardAll(includeUntracked: true);
    await actions.undo();
    await actions.redo();

    expect(await file('kept.txt').readAsString(), 'committed\n');
    expect(await file('new.txt').exists(), isFalse);
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test('a clean tree records nothing', () async {
    await g(['checkout', '--', '.']);
    await g(['reset', '-q', 'HEAD']);
    await g(['checkout', '--', '.']);
    await file('new.txt').delete();
    final c = container();

    await c
        .read(repoActionsProvider(repo.path))
        .discardAll(includeUntracked: true);

    expect(c.read(undoProvider(repo.path)).canUndo, isFalse);
  });

  test('a deleted tracked file comes back', () async {
    await file('kept.txt').delete();
    final c = container();

    await c.read(repoActionsProvider(repo.path)).discardAll();

    expect(await file('kept.txt').readAsString(), 'committed\n');
  });
}
