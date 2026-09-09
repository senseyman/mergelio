// A pick that applies to nothing pauses the rebase without a conflict. It
// happens whenever a commit already landed upstream under a different sha (a
// squash-merged pull request is the common case), and the todo the rebase
// editor writes names it explicitly, so git obeys the pick instead of skipping
// the commit the way a plain `git rebase` would.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
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

  bool rebaseInProgress() =>
      Directory('${dir.path}/.git/rebase-merge').existsSync() ||
      Directory('${dir.path}/.git/rebase-apply').existsSync();

  /// Builds the shape that stops a rebase on an empty pick: `upstream` is a
  /// commit on the branch that main also carries under a different sha but with
  /// an identical tree, followed by work only the branch has.
  ///
  /// Returns (onto, upstream, work).
  Future<(String, String, String)> divergedUpstream() async {
    await commit('base.txt', 'base\n', 'base');
    final upstream = await commit('feature.txt', 'feature\n', 'feature #20');
    await g(['branch', 'mine']);
    // Main lands the same change under a new sha, exactly as a squash-merge or
    // a maintainer's rebase does.
    await g(['commit', '-q', '--amend', '-m', 'feature #20 (merged)']);
    final onto = await out(['rev-parse', 'HEAD']);
    await g(['checkout', '-q', 'mine']);
    final work = await commit('work.txt', 'work\n', 'my work');
    return (onto, upstream, work);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_emptypick_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'rebaseSkip drops the paused commit and lets the rebase finish',
    () async {
      final (onto, upstream, work) = await divergedUpstream();
      final writer = GitWriter(svc, dir.path);

      await expectLater(
        writer.rebase(onto, 'pick $upstream\npick $work\n'),
        throwsA(isA<GitException>()),
      );
      expect(rebaseInProgress(), isTrue, reason: 'expected a paused rebase');

      await writer.rebaseSkip();

      expect(rebaseInProgress(), isFalse);
      expect((await out(['log', '--format=%s'])).split('\n'), [
        'my work',
        'feature #20 (merged)',
        'base',
      ]);
    },
  );

  test(
    'an empty pick leaves the rebase paused rather than aborting it',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));
      final (onto, upstream, work) = await divergedUpstream();

      await actions.rebase(onto, [
        RebaseStep(upstream, RebaseAction.pick),
        RebaseStep(work, RebaseAction.pick),
      ]);

      // Nothing to resolve, but the rebase is recoverable — throwing it away
      // would discard the work already replayed and leave the user with only the
      // terminal as a way back in.
      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(rebaseInProgress(), isTrue);
      final pending = await actions.pendingOp();
      expect(pending?.kind, MergeKind.rebase);
      expect(pending?.continues, isTrue);
    },
  );

  test('aborting from the paused state puts the branch back', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    final (onto, upstream, work) = await divergedUpstream();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.rebase(onto, [
      RebaseStep(upstream, RebaseAction.pick),
      RebaseStep(work, RebaseAction.pick),
    ]);
    // The other half of what the working-tree panel offers while paused.
    await actions.abortMerge();

    expect(rebaseInProgress(), isFalse);
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'mine');
  });

  test('a rebase finished by skipping an empty pick is undoable', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    final (onto, upstream, work) = await divergedUpstream();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.rebase(onto, [
      RebaseStep(upstream, RebaseAction.pick),
      RebaseStep(work, RebaseAction.pick),
    ]);
    await actions.continueOp();
    expect(await out(['rev-parse', 'HEAD']), isNot(before));

    // Skipping a step of a rebase is not like skipping a lone cherry-pick: the
    // remaining steps still replay, so the branch moves and has to be undoable.
    await actions.undo();

    expect(await out(['rev-parse', 'HEAD']), before);
    expect((await out(['log', '--format=%s'])).split('\n'), [
      'my work',
      'feature #20',
      'base',
    ]);
  });

  test('continuing a rebase paused on an empty pick finishes it', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    final (onto, upstream, work) = await divergedUpstream();

    await actions.rebase(onto, [
      RebaseStep(upstream, RebaseAction.pick),
      RebaseStep(work, RebaseAction.pick),
    ]);
    await actions.continueOp();

    expect(rebaseInProgress(), isFalse);
    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    // The already-upstream commit is dropped, not duplicated.
    expect((await out(['log', '--format=%s'])).split('\n'), [
      'my work',
      'feature #20 (merged)',
      'base',
    ]);
  });
}
