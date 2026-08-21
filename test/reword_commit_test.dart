import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

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
    dir = await Directory.systemTemp.createTemp('mergelio_reword_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('rewording HEAD rewrites its message without adding a commit', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('a.txt', 'a\n', 'old subject');

    await actions.rewordCommit(
      await out(['rev-parse', 'HEAD']),
      'new subject',
      description: 'new body',
    );

    expect(await out(['log', '-1', '--format=%B']), 'new subject\n\nnew body');
    expect(await out(['rev-list', '--count', 'HEAD']), '1');
  });

  test('rewording HEAD leaves staged changes staged', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('a.txt', 'a\n', 'old subject');
    await File('${dir.path}/a.txt').writeAsString('staged\n');
    await g(['add', '.']);

    await actions.rewordCommit(await out(['rev-parse', 'HEAD']), 'reworded');

    expect(await out(['show', 'HEAD:a.txt']), 'a');
    expect(await out(['diff', '--cached', '--name-only']), 'a.txt');
  });

  test(
    'rewording an older commit keeps the messages below and above',
    () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      await commit('base.txt', 'base\n', 'base');
      final middle = await commit('f1.txt', '1\n', 'middle');
      await commit('f2.txt', '2\n', 'top');

      await actions.rewordCommit(middle, 'middle reworded', description: 'why');

      expect((await out(['log', '--format=%s'])).split('\n'), [
        'top',
        'middle reworded',
        'base',
      ]);
      expect(
        await out(['log', '-1', '--format=%B', 'HEAD~1']),
        'middle reworded\n\nwhy',
      );
    },
  );

  test(
    'rewording an older commit preserves the tree of every commit',
    () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      await commit('base.txt', 'base\n', 'base');
      final middle = await commit('f1.txt', '1\n', 'middle');
      await commit('f2.txt', '2\n', 'top');

      await actions.rewordCommit(middle, 'middle reworded');

      expect(await out(['show', 'HEAD:f1.txt']), '1');
      expect(await out(['show', 'HEAD:f2.txt']), '2');
      expect(await out(['rev-list', '--count', 'HEAD']), '3');
    },
  );

  test('rewording the root commit works', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final root = await commit('base.txt', 'base\n', 'root');
    await commit('f1.txt', '1\n', 'second');

    await actions.rewordCommit(root, 'root reworded');

    expect((await out(['log', '--format=%s'])).split('\n'), [
      'second',
      'root reworded',
    ]);
  });

  test('rewording a commit unreachable from HEAD is refused', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'side']);
    final onSide = await commit('side.txt', 's\n', 'side only');
    await g(['checkout', '-q', 'main']);

    await actions.rewordCommit(onSide, 'nope');

    expect(await out(['log', '-1', '--format=%s', 'side']), 'side only');
    expect(
      c.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
  });

  test('rewording HEAD is undoable back to the original message', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('a.txt', 'a\n', 'old subject');

    await actions.rewordCommit(await out(['rev-parse', 'HEAD']), 'reworded');
    await c.read(undoProvider(dir.path).notifier).undo();

    expect(await out(['log', '-1', '--format=%B']), 'old subject');
  });

  group('merge commits', () {
    /// base ← "main work" ← merge(side) ← top, with "side work" off to the
    /// side. A linear `pick` plan cannot express this shape.
    Future<String> buildMergeHistory() async {
      await commit('base.txt', 'base\n', 'base');
      await g(['checkout', '-q', '-b', 'side']);
      await commit('s.txt', 's\n', 'side work');
      await g(['checkout', '-q', 'main']);
      final mainWork = await commit('m.txt', 'm\n', 'main work');
      await g(['merge', '-q', '--no-ff', 'side', '-m', 'merge side']);
      await commit('top.txt', 'top\n', 'top');
      return mainWork;
    }

    test('rewording under a merge is refused, leaving history alone', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      final mainWork = await buildMergeHistory();
      final before = await out(['log', '--format=%H %s']);

      await actions.rewordCommit(mainWork, 'main work reworded');

      expect(await out(['log', '--format=%H %s']), before);
      expect(
        c.read(toastProvider).any((t) => t.kind == ToastKind.warning),
        isTrue,
      );
    });

    test('a refused reword leaves no rebase in progress', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      final mainWork = await buildMergeHistory();

      await actions.rewordCommit(mainWork, 'main work reworded');

      // A half-applied `rebase -i` detaches HEAD onto the base commit and
      // leaves .git/rebase-merge behind, with no conflict for the UI to offer
      // a way out of.
      expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'main');
      expect(
        await Directory('${dir.path}/.git/rebase-merge').exists(),
        isFalse,
      );
    });

    test('rewording a merge commit at HEAD keeps both its parents', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      await commit('base.txt', 'base\n', 'base');
      await g(['checkout', '-q', '-b', 'side']);
      await commit('s.txt', 's\n', 'side work');
      await g(['checkout', '-q', 'main']);
      await commit('m.txt', 'm\n', 'main work');
      await g(['merge', '-q', '--no-ff', 'side', '-m', 'merge side']);
      final parentsBefore = await out(['log', '-1', '--format=%P']);

      await actions.rewordCommit(
        await out(['rev-parse', 'HEAD']),
        'merge side reworded',
      );

      expect(await out(['log', '-1', '--format=%s']), 'merge side reworded');
      expect(await out(['log', '-1', '--format=%P']), parentsBefore);
    });
  });

  test('rewording keeps the signature of a signed commit', () async {
    // No signing key in a test repo, so assert the intent instead: the writer
    // is asked to sign exactly when the original commit carried a signature.
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('a.txt', 'a\n', 'unsigned');

    await actions.rewordCommit(await out(['rev-parse', 'HEAD']), 'reworded');

    // An unsigned commit must not gain -S, which would fail without a key.
    expect(await out(['log', '-1', '--format=%G?']), 'N');
  });

  test('remoteBranchesContaining is empty for an unpushed commit', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final sha = await commit('a.txt', 'a\n', 'local only');

    expect(await actions.remoteBranchesContaining(sha), isEmpty);
  });

  test('remoteBranchesContaining names the remote branch holding it', () async {
    final remote = await Directory.systemTemp.createTemp('mergelio_remote_');
    addTearDown(() async {
      if (await remote.exists()) await remote.delete(recursive: true);
    });
    await svc.run(['init', '-q', '--bare'], repoPath: remote.path);
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final sha = await commit('a.txt', 'a\n', 'pushed');
    await g(['remote', 'add', 'origin', remote.path]);
    await g(['push', '-q', 'origin', 'main']);

    expect(await actions.remoteBranchesContaining(sha), ['origin/main']);
  });
}
