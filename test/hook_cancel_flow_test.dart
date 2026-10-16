import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';

/// A slow hook must not be killed by the ordinary timeout, so the only way out
/// of one is the busy bar's Cancel. These run real git against a hook that
/// sleeps far longer than the test is willing to wait.
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out.trim();

  Future<void> write(String file, String text) =>
      File('${dir.path}/$file').writeAsString('$text\n');

  Future<void> slowHook(String name) async {
    final f = File('${dir.path}/.git/hooks/$name');
    await f.writeAsString('#!/bin/sh\nsleep 20\n');
    await Process.run('chmod', ['+x', f.path]);
  }

  late ProviderContainer c;
  late RepoActions actions;
  late List<BusyState?> seen;

  List<String> toastTitles() => [
    for (final t in c.read(toastProvider)) t.title,
  ];

  Future<void> cancelWhenOffered() async {
    final until = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(until)) {
      final cancel = seen.lastOrNull?.onCancel;
      if (cancel != null) {
        // Let git get into the hook first.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return cancel();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Cancel was never offered');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_hookcancel_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await write('f.txt', 'base');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    c = ProviderContainer();
    actions = c.read(repoActionsProvider(dir.path));
    seen = [];
    c.listen(busyProvider, (_, next) => seen.add(next));
  });

  tearDown(() async {
    c.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a commit stuck in its pre-commit hook can be cancelled', () async {
    final before = await out(['rev-parse', 'HEAD']);
    await write('f.txt', 'changed');
    await g(['add', '.']);
    await slowHook('pre-commit');

    final watch = Stopwatch()..start();
    final run = actions.commit('msg');
    await cancelWhenOffered();
    final outcome = await run;

    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    expect(outcome.committed, isFalse);
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(toastTitles(), contains('Commit cancelled'));
    expect(toastTitles(), isNot(contains('Commit failed')));
    expect(c.read(busyProvider), isNull);
    // The next commit is not blocked by a lock the killed one left behind.
    expect(File('${dir.path}/.git/index.lock').existsSync(), isFalse);
  });

  test('a merge stuck in its pre-merge-commit hook can be cancelled', () async {
    await g(['checkout', '-q', '-b', 'topic']);
    await write('g.txt', 'topic');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'topic']);
    await g(['checkout', '-q', 'main']);
    final before = await out(['rev-parse', 'HEAD']);
    await slowHook('pre-merge-commit');

    final watch = Stopwatch()..start();
    final run = actions.merge('topic');
    await cancelWhenOffered();
    await run;

    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(toastTitles(), contains('Merge cancelled'));
    expect(toastTitles(), isNot(contains('Merge failed')));
    expect(c.read(busyProvider), isNull);
    // Killed in the hook, git has already staged the merged tree but written
    // no MERGE_HEAD. Left there, it reads as the user's own staged work and
    // the next commit folds the branch in as an ordinary commit.
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test('a cancelled merge keeps unrelated uncommitted edits', () async {
    await g(['checkout', '-q', '-b', 'topic']);
    await write('g.txt', 'topic');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'topic']);
    await g(['checkout', '-q', 'main']);
    await write('f.txt', 'mine');
    await slowHook('pre-merge-commit');

    final run = actions.merge('topic');
    await cancelWhenOffered();
    await run;

    expect(await out(['status', '--porcelain']), 'M f.txt');
    expect(await File('${dir.path}/f.txt').readAsString(), 'mine\n');
  });

  test('a cherry-pick continue stuck in a hook can be cancelled', () async {
    await g(['checkout', '-q', '-b', 'topic']);
    await write('f.txt', 'topic');
    await g(['commit', '-q', '-am', 'topic']);
    await g(['checkout', '-q', 'main']);
    await write('f.txt', 'main');
    await g(['commit', '-q', '-am', 'main']);
    final before = await out(['rev-parse', 'HEAD']);
    // Conflicts, as intended: both sides rewrote the same line.
    await svc.run(['cherry-pick', 'topic'], repoPath: dir.path);
    await write('f.txt', 'resolved');
    await g(['add', '.']);
    await slowHook('pre-commit');

    final watch = Stopwatch()..start();
    final run = actions.continueOp();
    await cancelWhenOffered();
    await run;

    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(
      toastTitles(),
      contains(
        allOf(startsWith('Continue cherry-pick '), endsWith(' cancelled')),
      ),
    );
    expect(c.read(busyProvider), isNull);
  });
}
