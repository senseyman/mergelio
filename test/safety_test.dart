import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_safety_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.txt').writeAsString('base\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('reset --hard auto-stashes uncommitted work (no silent loss)', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = (await svc.run(['rev-parse', 'HEAD'], repoPath: dir.path)).out;
    await File('${dir.path}/a.txt').writeAsString('committed change\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'second']);

    // Now uncommitted work on top.
    await File('${dir.path}/a.txt').writeAsString('UNCOMMITTED\n');

    await actions.resetHard(base);

    // Branch moved to base, but the uncommitted work is preserved in a stash.
    expect(
      (await svc.run(['rev-parse', 'HEAD'], repoPath: dir.path)).out,
      base,
    );
    expect(await GitReader(svc, dir.path).stashes(), isNotEmpty);
  });

  test(
    'undo of an auto-stashed reset pops the work back into the tree',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      final base = (await svc.run([
        'rev-parse',
        'HEAD',
      ], repoPath: dir.path)).out;
      await File('${dir.path}/a.txt').writeAsString('committed\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'second']);

      await File('${dir.path}/a.txt').writeAsString('UNCOMMITTED\n');
      await actions.resetHard(base);
      // Auto-stashed away → tree clean at base.
      expect(await File('${dir.path}/a.txt').readAsString(), 'base\n');

      await actions.undo();

      // Undo is a true inverse: back on 'second' with the uncommitted edit
      // restored to the working tree (not orphaned in a stash).
      expect(await File('${dir.path}/a.txt').readAsString(), 'UNCOMMITTED\n');
      expect(await GitReader(svc, dir.path).stashes(), isEmpty);
    },
  );

  test(
    'undo of reset restores the branch via the captured (reflog) sha',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      final base = (await svc.run([
        'rev-parse',
        'HEAD',
      ], repoPath: dir.path)).out;
      await File('${dir.path}/a.txt').writeAsString('two\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'two']);
      final after = (await svc.run([
        'rev-parse',
        'HEAD',
      ], repoPath: dir.path)).out;

      await actions.resetHard(base);
      await actions.undo();

      // The commit unreachable from any branch is recovered via its reflog sha.
      expect(
        (await svc.run(['rev-parse', 'HEAD'], repoPath: dir.path)).out,
        after,
      );
    },
  );
}
