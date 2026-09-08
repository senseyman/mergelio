import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/ui/shell/repo_op_dialogs.dart';

/// Reverting and cherry-picking a merge commit: git refuses both without a
/// mainline parent, so the app has to pass one through.
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out.trim();

  Future<String> commit(String file, String content, String msg) async {
    await File('${dir.path}/$file').writeAsString(content);
    await g(['add', '.']);
    await g(['commit', '-q', '-m', msg]);
    return out(['rev-parse', 'HEAD']);
  }

  bool exists(String file) => File('${dir.path}/$file').existsSync();

  /// base on main, `feature` adds f.txt, main adds m.txt, then feature is
  /// merged with --no-ff. Returns the merge sha, with main checked out.
  Future<String> mergeOfFeature() async {
    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'feature']);
    await commit('f.txt', 'feature\n', 'feature work');
    await g(['checkout', '-q', 'main']);
    await commit('m.txt', 'main\n', 'main work');
    await g(['merge', '--no-ff', '-q', '-m', 'merge feature', 'feature']);
    return out(['rev-parse', 'HEAD']);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_mainline_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('reverting a merge against parent 1 undoes the merged branch', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final merge = await mergeOfFeature();
    expect(exists('f.txt'), isTrue);

    await actions.revert(merge, mainline: 1);

    expect(exists('f.txt'), isFalse, reason: 'feature side is reverted');
    expect(exists('m.txt'), isTrue, reason: 'mainline side is kept');
    expect(await out(['log', '-1', '--format=%s']), contains('Revert'));
  });

  test('reverting a merge against parent 2 undoes the mainline side', () async {
    final writer = GitWriter(svc, dir.path);
    final merge = await mergeOfFeature();

    await writer.revert(merge, mainline: 2);

    expect(exists('m.txt'), isFalse);
    expect(exists('f.txt'), isTrue);
  });

  test('reverting a plain commit still needs no mainline', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('base.txt', 'base\n', 'base');
    final sha = await commit('gone.txt', 'x\n', 'add gone');

    await actions.revert(sha);

    expect(exists('gone.txt'), isFalse);
  });

  test(
    'cherry-picking a merge replays the diff against its mainline',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      // integ merges topic; main knows about neither.
      await commit('base.txt', 'base\n', 'base');
      await g(['checkout', '-q', '-b', 'topic']);
      await commit('t.txt', 'topic\n', 'topic work');
      await g(['checkout', '-q', '-b', 'integ', 'main']);
      await commit('i.txt', 'integ\n', 'integ work');
      await g(['merge', '--no-ff', '-q', '-m', 'merge topic', 'topic']);
      final merge = await out(['rev-parse', 'HEAD']);
      await g(['checkout', '-q', 'main']);

      await actions.cherryPick(merge, mainline: 1);

      expect(exists('t.txt'), isTrue, reason: 'topic side is replayed');
      expect(exists('i.txt'), isFalse, reason: 'mainline side is not');
    },
  );

  group('replayCommit', () {
    late ProviderContainer c;
    late RepoActions actions;

    setUp(() {
      c = ProviderContainer();
      addTearDown(c.dispose);
      actions = c.read(repoActionsProvider(dir.path));
    });

    Future<Commit> head() async {
      final commits = await GitReader(svc, dir.path).commits(maxCount: 1);
      return commits.first;
    }

    test('a merge asks for the mainline and passes it on', () async {
      await mergeOfFeature();
      var asked = 0;

      await replayCommit(
        commit: await head(),
        op: MainlineOp.revert,
        actions: actions,
        pick: () async {
          asked++;
          return 2;
        },
      );

      expect(asked, 1);
      expect(exists('m.txt'), isFalse, reason: 'parent 2 was picked');
      expect(exists('f.txt'), isTrue);
    });

    test('cancelling the picker leaves the repository alone', () async {
      final merge = await mergeOfFeature();

      await replayCommit(
        commit: await head(),
        op: MainlineOp.revert,
        actions: actions,
        pick: () async => null,
      );

      expect(await out(['rev-parse', 'HEAD']), merge);
      expect(exists('f.txt'), isTrue);
    });

    test('a plain commit is replayed without asking', () async {
      await commit('base.txt', 'base\n', 'base');
      await commit('gone.txt', 'x\n', 'add gone');
      var asked = 0;

      await replayCommit(
        commit: await head(),
        op: MainlineOp.revert,
        actions: actions,
        pick: () async {
          asked++;
          return 1;
        },
      );

      expect(asked, 0);
      expect(exists('gone.txt'), isFalse);
    });
  });
}
