import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/merge_session.dart';
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
    dir = await Directory.systemTemp.createTemp('mergelio_split_');
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

  Future<bool> rebasing() =>
      Directory('${dir.path}/.git/rebase-merge').exists();

  /// base ← "two files" (a.txt + b.txt) ← top.
  Future<String> buildHistory() async {
    await commit('base.txt', 'base\n', 'base');
    await File('${dir.path}/a.txt').writeAsString('a\n');
    final middle = await commit('b.txt', 'b\n', 'two files');
    await commit('top.txt', 'top\n', 'top');
    return middle;
  }

  test('splitting stops on the commit with its changes unstaged', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final middle = await buildHistory();

    await actions.splitCommit(middle);

    expect(await rebasing(), isTrue);
    expect(await out(['log', '-1', '--format=%s']), 'base');
    // Nothing staged: the user picks the pieces. Files the commit added are
    // still tracked, so they read as part of it rather than as stray files.
    expect(await out(['diff', '--cached', '--name-only']), '');
    expect((await out(['diff', '--name-only'])).split('\n'), [
      'a.txt',
      'b.txt',
    ]);
    expect(await out(['ls-files', '--others', '--exclude-standard']), '');
    final pending = await actions.pendingOp();
    expect(pending?.kind, MergeKind.rebase);
    expect(pending?.stop, const RebaseStop.split());
  });

  test(
    'the parts the user commits replace the commit; the rest replays',
    () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      final middle = await buildHistory();

      await actions.splitCommit(middle);
      await g(['add', 'a.txt']);
      await g(['commit', '-q', '-m', 'part a']);
      await g(['add', 'b.txt']);
      await g(['commit', '-q', '-m', 'part b']);
      await actions.continueOp();

      expect(await rebasing(), isFalse);
      expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'main');
      expect((await out(['log', '--format=%s'])).split('\n'), [
        'top',
        'part b',
        'part a',
        'base',
      ]);
      expect(await out(['show', 'HEAD:top.txt']), 'top');
    },
  );

  test('the composer is offered the original message, body included', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('base.txt', 'base\n', 'base');
    await File('${dir.path}/a.txt').writeAsString('a\n');
    await File('${dir.path}/b.txt').writeAsString('b\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'two files', '-m', 'why both']);
    final middle = await out(['rev-parse', 'HEAD']);
    await commit('top.txt', 'top\n', 'top');

    await actions.splitCommit(middle);

    expect(c.read(composerPrefillProvider(dir.path)), 'two files\n\nwhy both');
  });

  test('a refused split leaves the composer alone', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final root = await commit('base.txt', 'base\n', 'root');
    await commit('f.txt', 'f\n', 'second');

    await actions.splitCommit(root);

    expect(c.read(composerPrefillProvider(dir.path)), isNull);
  });

  test('a finished split is undoable back to the original commit', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final middle = await buildHistory();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.splitCommit(middle);
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'part a']);
    await g(['add', 'b.txt']);
    await g(['commit', '-q', '-m', 'part b']);
    await actions.continueOp();
    await c.read(undoProvider(dir.path).notifier).undo();

    expect(await out(['rev-parse', 'HEAD']), before);
  });

  test('continuing with changes left uncommitted commits nothing', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final middle = await buildHistory();

    await actions.splitCommit(middle);
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'part a']);
    await g(['add', 'b.txt']);
    final head = await out(['rev-parse', 'HEAD']);
    await actions.continueOp();

    expect(await rebasing(), isTrue);
    expect(await out(['rev-parse', 'HEAD']), head);
    expect(await out(['diff', '--cached', '--name-only']), 'b.txt');
  });

  test('aborting puts the branch back exactly as it was', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final middle = await buildHistory();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.splitCommit(middle);
    await actions.abortMerge();

    expect(await rebasing(), isFalse);
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(await out(['status', '--porcelain']), '');
  });

  test('asking again while paused keeps the parts already committed', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('base.txt', 'base\n', 'base');
    final one = await commit('one.txt', '1\n', 'one');
    await File('${dir.path}/a.txt').writeAsString('a\n');
    final middle = await commit('b.txt', 'b\n', 'two files');
    await commit('top.txt', 'top\n', 'top');

    await actions.splitCommit(middle);
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'part a']);
    final head = await out(['rev-parse', 'HEAD']);
    // Still below HEAD, so it gets as far as the rebase, which is refused.
    await actions.splitCommit(one);

    expect(await out(['rev-parse', 'HEAD']), head);
    expect(await out(['log', '-1', '--format=%s']), 'part a');
  });

  test('HEAD itself can be split', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('base.txt', 'base\n', 'base');
    await File('${dir.path}/a.txt').writeAsString('a\n');
    final head = await commit('b.txt', 'b\n', 'two files');

    await actions.splitCommit(head);

    expect(await rebasing(), isTrue);
    expect(await out(['log', '-1', '--format=%s']), 'base');
    expect(await out(['diff', '--cached', '--name-only']), '');
  });

  test('the root commit is refused, leaving history alone', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final root = await commit('base.txt', 'base\n', 'root');
    await commit('f.txt', 'f\n', 'second');
    final before = await out(['rev-parse', 'HEAD']);

    await actions.splitCommit(root);

    expect(await rebasing(), isFalse);
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(
      c.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
  });

  test('a commit not on the current branch is refused', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'side']);
    final onSide = await commit('side.txt', 's\n', 'side only');
    await g(['checkout', '-q', 'main']);

    await actions.splitCommit(onSide);

    expect(await rebasing(), isFalse);
    expect(await out(['log', '-1', '--format=%s', 'side']), 'side only');
    expect(
      c.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
  });

  test('a commit under a merge is refused, leaving history alone', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'side']);
    await commit('s.txt', 's\n', 'side work');
    await g(['checkout', '-q', 'main']);
    final mainWork = await commit('m.txt', 'm\n', 'main work');
    await g(['merge', '-q', '--no-ff', 'side', '-m', 'merge side']);
    final before = await out(['log', '--format=%H %s']);

    await actions.splitCommit(mainWork);

    expect(await rebasing(), isFalse);
    expect(await out(['log', '--format=%H %s']), before);
    expect(
      c.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
  });

  test('a merge commit itself is refused', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'side']);
    await commit('s.txt', 's\n', 'side work');
    await g(['checkout', '-q', 'main']);
    await commit('m.txt', 'm\n', 'main work');
    await g(['merge', '-q', '--no-ff', 'side', '-m', 'merge side']);
    final merge = await out(['rev-parse', 'HEAD']);

    await actions.splitCommit(merge);

    expect(await rebasing(), isFalse);
    expect(await out(['rev-parse', 'HEAD']), merge);
    expect(
      c.read(toastProvider).map((t) => t.description),
      contains('A merge commit cannot be split.'),
    );
  });
}
