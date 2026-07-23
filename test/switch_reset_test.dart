import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory origin;
  late Directory clone;
  const svc = SystemGitService();

  Future<void> g(Directory d, List<String> a) async {
    final r = await svc.run(a, repoPath: d.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  Future<String> sha(Directory d, String ref) async =>
      (await svc.run(['rev-parse', ref], repoPath: d.path)).out;

  setUp(() async {
    origin = await Directory.systemTemp.createTemp('mergelio_sr_origin_');
    await g(origin, ['init', '-q', '-b', 'main']);
    await g(origin, ['config', 'user.email', 't@e.com']);
    await g(origin, ['config', 'user.name', 'T']);
    await g(origin, ['config', 'commit.gpgsign', 'false']);
    await File('${origin.path}/a.txt').writeAsString('base\n');
    await g(origin, ['add', '.']);
    await g(origin, ['commit', '-q', '-m', 'base']);

    clone = await Directory.systemTemp.createTemp('mergelio_sr_clone_');
    await svc.run(['clone', '-q', origin.path, clone.path]);
    await g(clone, ['config', 'user.email', 't@e.com']);
    await g(clone, ['config', 'user.name', 'T']);
    await g(clone, ['config', 'commit.gpgsign', 'false']);
    // Local main gets an extra commit → diverged from origin/main.
    await File('${clone.path}/b.txt').writeAsString('local\n');
    await g(clone, ['add', '.']);
    await g(clone, ['commit', '-q', '-m', 'local only']);
  });

  tearDown(() async {
    for (final d in [origin, clone]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  RemoteBranch rbMain() => const RemoteBranch(
    remote: 'origin',
    branch: 'main',
    hasLocal: true,
    tip: '',
  );

  test('resets local main to origin/main, stashing dirty work', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(clone.path));
    final originSha = await sha(clone, 'origin/main');

    // Dirty the tree so the auto-stash path runs.
    await File('${clone.path}/a.txt').writeAsString('dirty\n');

    await actions.switchResettingToRemote(rbMain());

    expect(await sha(clone, 'HEAD'), originSha);
    expect(await sha(clone, 'main'), originSha);
    expect(
      (await svc.run([
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ], repoPath: clone.path)).out,
      'main',
    );
    expect(await GitReader(svc, clone.path).stashes(), isNotEmpty);
  });

  test('undo restores the local sha, branch and stashed work', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(clone.path));
    final localSha = await sha(clone, 'main');

    await File('${clone.path}/a.txt').writeAsString('dirty\n');
    await actions.switchResettingToRemote(rbMain());
    await actions.undo();

    expect(await sha(clone, 'main'), localSha);
    expect(await File('${clone.path}/a.txt').readAsString(), 'dirty\n');
    expect(await GitReader(svc, clone.path).stashes(), isEmpty);
  });
}
