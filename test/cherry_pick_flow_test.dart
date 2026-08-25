import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_service.dart';
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

  /// Resolves every hunk of every file in the session to [r] and finishes it.
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
    await actions.finishMerge(session);
  }

  /// Builds base → main-change on main, plus a `feature` commit off base that
  /// touches the same line. Returns the feature tip, with main checked out.
  Future<String> conflictingPick() async {
    await commit('a.txt', 'base\n', 'base');
    await commit('a.txt', 'main-change\n', 'main edit');
    await g(['checkout', '-q', '-b', 'feature', 'HEAD~1']);
    final tip = await commit('a.txt', 'feature-change\n', 'feature edit');
    await g(['checkout', '-q', 'main']);
    return tip;
  }

  bool sequencerFile(String name) =>
      File('${dir.path}/.git/$name').existsSync();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_pick_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a clean cherry-pick commits and is undoable', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('a.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'feature']);
    final tip = await commit('b.txt', 'B\n', 'feature edit');
    await g(['checkout', '-q', 'main']);

    await actions.cherryPick(tip);

    expect(await out(['log', '-1', '--format=%s']), 'feature edit');
    expect(c.read(mergeSessionProvider(dir.path)), isNull);

    await actions.undo();
    expect(await out(['log', '-1', '--format=%s']), 'base');
  });

  test(
    'a conflicting cherry-pick opens the tool; finish continues the pick',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));
      final tip = await conflictingPick();

      await actions.cherryPick(tip);

      final session = c.read(mergeSessionProvider(dir.path));
      expect(session?.kind, MergeKind.cherryPick);
      expect(session?.files, isNotEmpty);
      expect(sequencerFile('CHERRY_PICK_HEAD'), isTrue);

      await resolveAll(c, actions, Resolution.theirs);

      // The pick landed as a commit and the sequencer state is gone.
      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(sequencerFile('CHERRY_PICK_HEAD'), isFalse);
      expect(await out(['log', '-1', '--format=%s']), 'feature edit');
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'feature-change\n');
      expect(await out(['status', '--porcelain']), isEmpty);
    },
  );

  test('a finished cherry-pick is undoable back to the prior HEAD', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    final tip = await conflictingPick();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.cherryPick(tip);
    await resolveAll(c, actions, Resolution.theirs);
    expect(await out(['rev-parse', 'HEAD']), isNot(before));

    await actions.undo();
    expect(await out(['rev-parse', 'HEAD']), before);
  });

  test('aborting a cherry-pick session restores a clean tree', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    final tip = await conflictingPick();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.cherryPick(tip);
    expect(c.read(mergeSessionProvider(dir.path))?.kind, MergeKind.cherryPick);

    await actions.abortMerge();

    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(sequencerFile('CHERRY_PICK_HEAD'), isFalse);
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test(
    'resolving a pick to ours skips the now-empty commit instead of stalling',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));
      final tip = await conflictingPick();
      final before = await out(['rev-parse', 'HEAD']);

      await actions.cherryPick(tip);
      // Keeping "ours" everywhere leaves nothing to commit; git refuses
      // `--continue` and wants `--skip`.
      await resolveAll(c, actions, Resolution.ours);

      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(sequencerFile('CHERRY_PICK_HEAD'), isFalse);
      expect(await out(['rev-parse', 'HEAD']), before);
      expect(await out(['status', '--porcelain']), isEmpty);
    },
  );

  test('a second pick is refused while one is paused on conflicts', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    final tip = await conflictingPick();
    // A second feature commit to try picking on top of the paused one.
    await g(['checkout', '-q', 'feature']);
    final second = await commit('b.txt', 'B\n', 'second feature edit');
    await g(['checkout', '-q', 'main']);

    await actions.cherryPick(tip);
    final paused = c.read(mergeSessionProvider(dir.path));
    expect(paused?.kind, MergeKind.cherryPick);

    await actions.cherryPick(second);

    // The paused session is left alone, not relabelled with the second sha.
    final after = c.read(mergeSessionProvider(dir.path));
    expect(after?.branch, paused?.branch);
    expect(after?.kind, MergeKind.cherryPick);
  });

  test('a pick that cannot start toasts and opens no session', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await commit('a.txt', 'base\n', 'base');

    await actions.cherryPick('0000000000000000000000000000000000000000');

    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(sequencerFile('CHERRY_PICK_HEAD'), isFalse);
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test('a conflicting revert opens the tool; finish continues it', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('x.txt', 'v1\n', 'v1');
    final target = await commit('x.txt', 'v2\n', 'v2');
    await commit('x.txt', 'v3\n', 'v3');

    await actions.revert(target);

    expect(c.read(mergeSessionProvider(dir.path))?.kind, MergeKind.revert);
    expect(sequencerFile('REVERT_HEAD'), isTrue);

    await resolveAll(c, actions, Resolution.theirs);

    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(sequencerFile('REVERT_HEAD'), isFalse);
    expect(await out(['log', '-1', '--format=%s']), startsWith('Revert'));
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test('aborting a revert session restores a clean tree', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('x.txt', 'v1\n', 'v1');
    final target = await commit('x.txt', 'v2\n', 'v2');
    final before = await commit('x.txt', 'v3\n', 'v3');

    await actions.revert(target);
    await actions.abortMerge();

    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(sequencerFile('REVERT_HEAD'), isFalse);
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test(
    'openConflictResolution reopens a cherry-pick left mid-flight',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));
      final tip = await conflictingPick();

      // A pick started outside the app (or before a restart).
      await svc.run(['cherry-pick', tip], repoPath: dir.path);
      await actions.openConflictResolution();

      expect(
        c.read(mergeSessionProvider(dir.path))?.kind,
        MergeKind.cherryPick,
      );
    },
  );

  test('openConflictResolution reopens a revert left mid-flight', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('x.txt', 'v1\n', 'v1');
    final target = await commit('x.txt', 'v2\n', 'v2');
    await commit('x.txt', 'v3\n', 'v3');

    await svc.run(['revert', '--no-edit', target], repoPath: dir.path);
    await actions.openConflictResolution();

    expect(c.read(mergeSessionProvider(dir.path))?.kind, MergeKind.revert);
  });
}
