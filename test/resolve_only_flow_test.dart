import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Resolving conflicts stages the result and stops there. Nothing is committed
/// until the user asks for it: a merge through the commit composer, a paused
/// rebase/cherry-pick/revert through [RepoActions.continueOp].
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

  /// Resolves every hunk of every file in the open session to [r] and hands it
  /// back to the actions, which stages it.
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
  }

  /// base → main edit on main, plus a `feature` branch off base touching the
  /// same line. Leaves main checked out; returns the feature tip.
  Future<String> conflictingFeature() async {
    await commit('a.txt', 'base\n', 'base');
    await commit('a.txt', 'main-change\n', 'main edit');
    await g(['checkout', '-q', '-b', 'feature', 'HEAD~1']);
    final tip = await commit('a.txt', 'feature-change\n', 'feature edit');
    await g(['checkout', '-q', 'main']);
    return tip;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_resolve_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('resolving a merge stages the result without committing', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await conflictingFeature();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.merge('feature');
    await resolveAll(c, actions, Resolution.theirs);

    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(await GitReader(svc, dir.path).conflictedFiles(), isEmpty);
    // HEAD has not moved and the merge is still open, waiting for the user.
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(File('${dir.path}/.git/MERGE_HEAD').existsSync(), isTrue);
    // The resolution is staged, ready to be reviewed.
    expect(await out(['diff', '--cached', '--name-only']), 'a.txt');
    expect(File('${dir.path}/a.txt').readAsStringSync(), 'feature-change\n');
    expect((await actions.pendingOp())?.kind, MergeKind.merge);
  });

  test('committing a resolved merge makes a real merge commit', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    final tip = await conflictingFeature();

    await actions.merge('feature');
    await resolveAll(c, actions, Resolution.theirs);
    await actions.commit('Merge feature');

    expect(await out(['rev-parse', 'HEAD^2']), tip);
    expect(await out(['log', '-1', '--format=%s']), 'Merge feature');
    expect(await actions.pendingOp(), isNull);
  });

  test('the composer offers git prepared merge message', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await conflictingFeature();

    await actions.merge('feature');
    await resolveAll(c, actions, Resolution.theirs);

    final msg = await actions.pendingMergeMessage();
    expect(msg, contains('feature'));
    // git's commented-out conflict list would otherwise land in the commit
    // body — `git commit -m` strips nothing.
    expect(msg, isNot(contains('#')));
  });

  test('a committed merge message carries no leftover conflict list', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await conflictingFeature();

    await actions.merge('feature');
    await resolveAll(c, actions, Resolution.theirs);
    final prepared = await actions.pendingMergeMessage();
    await actions.commit(prepared);

    expect(await out(['log', '-1', '--format=%B']), isNot(contains('#')));
  });

  test('undoing a merge commit restores the pre-merge HEAD', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await conflictingFeature();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.merge('feature');
    await resolveAll(c, actions, Resolution.theirs);
    await actions.commit('Merge feature');
    await actions.undo();

    expect(await out(['rev-parse', 'HEAD']), before);

    // Redo restores the merge commit itself — its second parent cannot be
    // recreated by committing the index again.
    await actions.redo();
    expect(
      (await svc.run(['rev-parse', 'HEAD^2'], repoPath: dir.path)).ok,
      isTrue,
    );
  });

  test(
    'resolving a cherry-pick stages it and leaves the pick paused',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));
      final tip = await conflictingFeature();
      final before = await out(['rev-parse', 'HEAD']);

      await actions.cherryPick(tip);
      await resolveAll(c, actions, Resolution.theirs);

      expect(await out(['rev-parse', 'HEAD']), before);
      expect(File('${dir.path}/.git/CHERRY_PICK_HEAD').existsSync(), isTrue);
      expect((await actions.pendingOp())?.kind, MergeKind.cherryPick);

      await actions.continueOp();

      expect(await out(['log', '-1', '--format=%s']), 'feature edit');
      expect(File('${dir.path}/.git/CHERRY_PICK_HEAD').existsSync(), isFalse);
      expect(await actions.pendingOp(), isNull);
    },
  );

  test('a continued cherry-pick is undoable back to the prior HEAD', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    final tip = await conflictingFeature();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.cherryPick(tip);
    await resolveAll(c, actions, Resolution.theirs);
    await actions.continueOp();
    await actions.undo();

    expect(await out(['rev-parse', 'HEAD']), before);
  });

  test('resolving a rebase stages it and leaves the rebase paused', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('x.txt', 'base\n', 'base');
    final a = await commit('x.txt', 'A\n', 'A');
    final b = await commit('x.txt', 'B\n', 'B');

    await actions.rebase(base, [
      RebaseStep(b, RebaseAction.pick),
      RebaseStep(a, RebaseAction.pick),
    ]);
    expect(c.read(mergeSessionProvider(dir.path))?.kind, MergeKind.rebase);

    await resolveAll(c, actions, Resolution.theirs);

    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(await actions.isRebaseInProgress(), isTrue);
    expect((await actions.pendingOp())?.kind, MergeKind.rebase);

    // Continuing may stop on the next conflict; keep resolving until done.
    var guard = 0;
    while (await actions.isRebaseInProgress() && guard++ < 5) {
      await actions.continueOp();
      if (c.read(mergeSessionProvider(dir.path)) != null) {
        await resolveAll(c, actions, Resolution.theirs);
      }
    }

    expect(await actions.isRebaseInProgress(), isFalse);
    expect(await actions.pendingOp(), isNull);
    expect((await out(['log', '--format=%s'])).split('\n'), ['A', 'B', 'base']);
  });

  test('a continue that conflicts again reopens the merge tool', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('x.txt', 'base\n', 'base');
    final a = await commit('x.txt', 'A\n', 'A');
    final b = await commit('x.txt', 'B\n', 'B');

    await actions.rebase(base, [
      RebaseStep(b, RebaseAction.pick),
      RebaseStep(a, RebaseAction.pick),
    ]);
    await resolveAll(c, actions, Resolution.theirs);
    await actions.continueOp();

    // The second pick conflicts as well, so a fresh session is waiting.
    expect(c.read(mergeSessionProvider(dir.path))?.kind, MergeKind.rebase);
  });

  test('aborting after the session closed still aborts the merge', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await conflictingFeature();
    final before = await out(['rev-parse', 'HEAD']);

    await actions.merge('feature');
    await resolveAll(c, actions, Resolution.theirs);
    await actions.abortMerge();

    expect(await out(['rev-parse', 'HEAD']), before);
    expect(File('${dir.path}/.git/MERGE_HEAD').existsSync(), isFalse);
    expect(File('${dir.path}/a.txt').readAsStringSync(), 'main-change\n');
    expect(await actions.pendingOp(), isNull);
  });

  test('an operation found in progress at launch is still reported', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await conflictingFeature();

    // Conflict the merge behind the app's back, as a crash or an outside
    // terminal would leave it.
    await svc.run(['merge', '--no-ff', 'feature'], repoPath: dir.path);

    expect((await actions.pendingOp())?.kind, MergeKind.merge);
  });
}
