import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  const svc = SystemGitService();
  late Directory origin;
  late Directory clone;

  Future<void> g(Directory d, List<String> a) async {
    final r = await svc.run(a, repoPath: d.path);
    if (!r.ok) throw StateError('git ${a.join(' ')}: ${r.err}');
  }

  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('mergelio_rb_');
    origin = Directory('${tmp.path}/origin')..createSync();
    await g(origin, ['init', '-q', '-b', 'main']);
    await g(origin, ['config', 'user.email', 't@e.com']);
    await g(origin, ['config', 'user.name', 'T']);
    await g(origin, ['config', 'commit.gpgsign', 'false']);
    await File('${origin.path}/a.txt').writeAsString('A\n');
    await g(origin, ['add', '.']);
    await g(origin, ['commit', '-q', '-m', 'main']);
    // A second branch on the origin.
    await g(origin, ['branch', 'feature/x']);

    clone = Directory('${tmp.path}/clone');
    await svc.run(['clone', '-q', origin.path, clone.path]);
    await g(clone, ['config', 'user.email', 't@e.com']);
    await g(clone, ['config', 'user.name', 'T']);
  });

  tearDown(() async {
    final parent = origin.parent;
    if (await parent.exists()) await parent.delete(recursive: true);
  });

  test(
    'remoteBranches lists origin branches, skips HEAD, flags hasLocal',
    () async {
      final reader = GitReader(svc, clone.path);
      final rbs = await reader.remoteBranches();
      final names = rbs.map((b) => b.name).toSet();

      expect(names, containsAll(['origin/main', 'origin/feature/x']));
      // The origin/HEAD symref is never listed.
      expect(names.any((n) => n.endsWith('/HEAD')), isFalse);
      // main has a local branch after clone; feature/x does not.
      expect(rbs.firstWhere((b) => b.branch == 'main').hasLocal, isTrue);
      expect(rbs.firstWhere((b) => b.branch == 'feature/x').hasLocal, isFalse);
    },
  );

  test('branch and remote-branch tips resolve to a real commit sha', () async {
    final reader = GitReader(svc, clone.path);
    final head = (await svc.run([
      'rev-parse',
      'HEAD',
    ], repoPath: clone.path)).out;

    final local = (await reader.branches()).firstWhere((b) => b.name == 'main');
    expect(local.tip, head);

    final remoteMain = (await reader.remoteBranches()).firstWhere(
      (b) => b.branch == 'main',
    );
    // A freshly-cloned main and origin/main point at the same commit.
    expect(remoteMain.tip, head);
    expect(remoteMain.tip.length, 40);
  });

  test(
    'checkoutRemote creates a local tracking branch; undo removes it',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(clone.path));
      final reader = GitReader(svc, clone.path);

      final feature = (await reader.remoteBranches()).firstWhere(
        (b) => b.branch == 'feature/x',
      );
      expect(feature.hasLocal, isFalse);

      await actions.checkoutRemote(feature);
      expect(
        (await svc.run([
          'rev-parse',
          '--abbrev-ref',
          'HEAD',
        ], repoPath: clone.path)).out,
        'feature/x',
      );
      // The new local branch tracks origin/feature/x.
      final upstream = await svc.run([
        'rev-parse',
        '--abbrev-ref',
        'feature/x@{upstream}',
      ], repoPath: clone.path);
      expect(upstream.out, 'origin/feature/x');

      await actions.undo();
      // Back on main and the created local branch is gone.
      expect(
        (await svc.run([
          'rev-parse',
          '--abbrev-ref',
          'HEAD',
        ], repoPath: clone.path)).out,
        'main',
      );
      final branches = await GitReader(svc, clone.path).branches();
      expect(branches.map((b) => b.name), isNot(contains('feature/x')));
    },
  );
}
