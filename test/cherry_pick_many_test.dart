import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_service.dart';
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
    return (await out(['rev-parse', 'HEAD'])).trim();
  }

  Future<List<String>> subjects(int n) async =>
      (await out(['log', '-$n', '--format=%s'])).trim().split('\n');

  bool gitPath(String name) =>
      FileSystemEntity.typeSync('${dir.path}/.git/$name') !=
      FileSystemEntityType.notFound;

  /// Resolves every hunk to [r], stages it and continues the paused sequence.
  Future<void> resolveAll(
    ProviderContainer c,
    RepoActions actions,
    Resolution r,
  ) async {
    var session = c.read(mergeSessionProvider(dir.path))!;
    for (var i = 0; i < session.files.length; i++) {
      var file = session.files[i];
      for (final h in file.hunkIndices) {
        file = file.withResolution(h, r);
      }
      session = session.replaceFile(i, file);
    }
    await actions.resolveConflicts(session);
    await actions.continueOp();
  }

  /// base → `main edit` on main; `feature` off base carries three commits, the
  /// middle one touching the line main changed. Returns the feature commits
  /// oldest first, with main checked out.
  Future<List<String>> featureWithConflictInMiddle() async {
    await commit('a.txt', 'base\n', 'base');
    await commit('a.txt', 'main-change\n', 'main edit');
    await g(['checkout', '-q', '-b', 'feature', 'HEAD~1']);
    final one = await commit('b.txt', 'B\n', 'one');
    final two = await commit('a.txt', 'feature-change\n', 'two');
    final three = await commit('c.txt', 'C\n', 'three');
    await g(['checkout', '-q', 'main']);
    return [one, two, three];
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_pick_many_');
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

  test('picks every commit in the order given, undone as one step', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('a.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'feature']);
    final one = await commit('b.txt', 'B\n', 'one');
    await commit('c.txt', 'C\n', 'skipped');
    final three = await commit('d.txt', 'D\n', 'three');
    await g(['checkout', '-q', 'main']);

    await actions.cherryPickMany([one, three]);

    expect(await subjects(3), ['three', 'one', 'base']);
    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(c.read(undoProvider(dir.path)).past, hasLength(1));

    await actions.undo();
    expect(await subjects(1), ['base']);
  });

  test('a conflict mid-sequence names the commit it stopped on; continuing '
      'replays the rest and the whole run undoes in one step', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final picks = await featureWithConflictInMiddle();
    final before = (await out(['rev-parse', 'HEAD'])).trim();

    await actions.cherryPickMany(picks);

    final session = c.read(mergeSessionProvider(dir.path));
    expect(session?.kind, MergeKind.cherryPick);
    expect(session?.branch, picks[1].substring(0, session!.branch.length));
    expect(session.prevSha, before);

    await resolveAll(c, actions, Resolution.theirs);

    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(gitPath('CHERRY_PICK_HEAD'), isFalse);
    expect(gitPath('sequencer'), isFalse);
    expect(await subjects(4), ['three', 'two', 'one', 'main edit']);

    await actions.undo();
    expect((await out(['rev-parse', 'HEAD'])).trim(), before);
  });

  test(
    'skipping the paused commit after earlier picks landed is still undoable',
    () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      final picks = await featureWithConflictInMiddle();
      final before = (await out(['rev-parse', 'HEAD'])).trim();

      await actions.cherryPickMany(picks);
      // Keeping main's side leaves nothing to commit: continue skips `two`.
      await resolveAll(c, actions, Resolution.ours);

      expect(await subjects(3), ['three', 'one', 'main edit']);
      expect(c.read(undoProvider(dir.path)).canUndo, isTrue);

      await actions.undo();
      expect((await out(['rev-parse', 'HEAD'])).trim(), before);
    },
  );

  group('without committing', () {
    test('stages every pick and leaves HEAD alone', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      await commit('a.txt', 'base\n', 'base');
      await g(['checkout', '-q', '-b', 'feature']);
      final one = await commit('b.txt', 'B\n', 'one');
      final two = await commit('c.txt', 'C\n', 'two');
      await g(['checkout', '-q', 'main']);
      final head = (await out(['rev-parse', 'HEAD'])).trim();

      await actions.cherryPickMany([one, two], noCommit: true);

      expect((await out(['rev-parse', 'HEAD'])).trim(), head);
      expect(
        (await out(['diff', '--cached', '--name-only'])).trim().split('\n'),
        ['b.txt', 'c.txt'],
      );
      expect(await out(['diff', '--name-only']), isEmpty);
      expect(gitPath('sequencer'), isFalse);
      expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
    });

    test('a conflict backs everything out and opens no session', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      final picks = await featureWithConflictInMiddle();
      final head = (await out(['rev-parse', 'HEAD'])).trim();

      await actions.cherryPickMany(picks, noCommit: true);

      expect((await out(['rev-parse', 'HEAD'])).trim(), head);
      expect(await out(['status', '--porcelain']), isEmpty);
      expect(gitPath('sequencer'), isFalse);
      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(c.read(toastProvider).last.kind, ToastKind.warning);
    });

    test('a lone conflicting pick is backed out too', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      final picks = await featureWithConflictInMiddle();

      await actions.cherryPickMany([picks[1]], noCommit: true);

      expect(await out(['status', '--porcelain']), isEmpty);
      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(c.read(toastProvider).last.kind, ToastKind.warning);
    });

    test('refuses over uncommitted edits and keeps them', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      await commit('a.txt', 'base\n', 'base');
      await g(['checkout', '-q', '-b', 'feature']);
      final one = await commit('b.txt', 'B\n', 'one');
      await g(['checkout', '-q', 'main']);
      await File('${dir.path}/a.txt').writeAsString('edited\n');

      await actions.cherryPickMany([one], noCommit: true);

      expect(File('${dir.path}/b.txt').existsSync(), isFalse);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'edited\n');
      expect(c.read(toastProvider).last.kind, ToastKind.warning);
    });

    test('ignores untracked files', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(dir.path));
      await commit('a.txt', 'base\n', 'base');
      await g(['checkout', '-q', '-b', 'feature']);
      final one = await commit('b.txt', 'B\n', 'one');
      await g(['checkout', '-q', 'main']);
      await File('${dir.path}/scratch.txt').writeAsString('mine\n');

      await actions.cherryPickMany([one], noCommit: true);

      expect((await out(['diff', '--cached', '--name-only'])).trim(), 'b.txt');
      expect(File('${dir.path}/scratch.txt').existsSync(), isTrue);
    });
  });
}
