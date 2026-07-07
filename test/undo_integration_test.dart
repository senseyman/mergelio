import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

/// Exercises the real-git inverse-command undo against a temp repo.
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_undo_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.txt').writeAsString('A\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'A']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  Future<Set<String>> branchNames() async =>
      (await GitReader(svc, dir.path).branches()).map((b) => b.name).toSet();

  test('undo removes a created branch; redo restores it', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));

    await actions.createBranch('feature');
    expect(await branchNames(), contains('feature'));
    expect(c.read(undoProvider(dir.path)).canUndo, isTrue);

    await actions.undo();
    expect(await branchNames(), isNot(contains('feature')));
    expect(c.read(undoProvider(dir.path)).canRedo, isTrue);

    await actions.redo();
    expect(await branchNames(), contains('feature'));
  });

  test('undo of a delete recreates the branch at its old commit', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await g(['branch', 'temp']);
    final sha = (await svc.run(['rev-parse', 'temp'], repoPath: dir.path)).out;

    await actions.deleteBranch('temp');
    expect(await branchNames(), isNot(contains('temp')));

    await actions.undo();
    expect(await branchNames(), contains('temp'));
    expect((await svc.run(['rev-parse', 'temp'], repoPath: dir.path)).out, sha);
  });

  test('checkout undo returns to the previous branch', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await g(['branch', 'feature']);

    await actions.checkout('feature');
    expect(
      (await GitReader(
        svc,
        dir.path,
      ).branches()).firstWhere((b) => b.current).name,
      'feature',
    );

    await actions.undo();
    expect(
      (await GitReader(
        svc,
        dir.path,
      ).branches()).firstWhere((b) => b.current).name,
      'main',
    );
  });

  test('rename undo restores the original branch name', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await g(['branch', 'old']);

    await actions.renameBranch('old', 'new');
    expect(await branchNames(), contains('new'));

    await actions.undo();
    expect(await branchNames(), contains('old'));
    expect(await branchNames(), isNot(contains('new')));
  });

  test('undo of an annotated-tag delete restores the right commit', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    await g(['tag', '-a', 'v1', '-m', 'release']);
    final commit = (await svc.run([
      'rev-parse',
      'v1^{commit}',
    ], repoPath: dir.path)).out;

    await actions.deleteTag('v1');
    await actions.undo();

    // Restored tag points at the original commit (not the old tag object).
    expect(
      (await svc.run(['rev-parse', 'v1^{commit}'], repoPath: dir.path)).out,
      commit,
    );
  });

  test('a conflicting cherry-pick aborts, leaving a clean tree', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    // main edits a.txt; feature edits the same line → cherry-pick conflicts.
    await File('${dir.path}/a.txt').writeAsString('main-change\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'main edit']);
    await g(['checkout', '-q', '-b', 'feature', 'HEAD~1']);
    await File('${dir.path}/a.txt').writeAsString('feature-change\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'feature edit']);
    final featureTip = (await svc.run([
      'rev-parse',
      'HEAD',
    ], repoPath: dir.path)).out;
    await g(['checkout', '-q', 'main']);

    await actions.cherryPick(featureTip);

    // No CHERRY_PICKING state and a clean tree (aborted, not stuck).
    expect(await GitReader(svc, dir.path).status(), isEmpty);
    expect(File('${dir.path}/.git/CHERRY_PICK_HEAD').existsSync(), isFalse);
  });

  test('undo of reset --hard returns to the prior commit', () async {
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));
    final before = (await svc.run([
      'rev-parse',
      'HEAD',
    ], repoPath: dir.path)).out;
    await File('${dir.path}/b.txt').writeAsString('B\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'B']);
    final after = (await svc.run([
      'rev-parse',
      'HEAD',
    ], repoPath: dir.path)).out;

    await actions.resetHard(before);
    expect(
      (await svc.run(['rev-parse', 'HEAD'], repoPath: dir.path)).out,
      before,
    );

    await actions.undo();
    expect(
      (await svc.run(['rev-parse', 'HEAD'], repoPath: dir.path)).out,
      after,
    );
  });
}
