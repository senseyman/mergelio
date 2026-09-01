import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> a) async {
    final r = await svc.run(a, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  // Sets up so `stash@{0}` conflicts when applied/popped onto HEAD.
  Future<void> primeStash() async {
    await File('${dir.path}/a.txt').writeAsString('base\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    await File('${dir.path}/a.txt').writeAsString('stashed\n');
    await g(['stash', 'push', '-q', '-m', 'work']);
    await File('${dir.path}/a.txt').writeAsString('other\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'other']);
  }

  // Leaves a conflicted `stash apply` in the tree (stash@{0} still present).
  Future<void> makeStashConflict() async {
    await primeStash();
    // Conflicting apply; ignore the non-zero exit.
    await svc.run(['stash', 'apply'], repoPath: dir.path);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_stashc_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'openConflictResolution opens a stash session for tree conflicts',
    () async {
      await makeStashConflict();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      await actions.openConflictResolution();

      final session = c.read(mergeSessionProvider(dir.path));
      expect(session, isNotNull);
      expect(session!.kind, MergeKind.stash);
      expect(session.files.map((f) => f.path), contains('a.txt'));
    },
  );

  test('openConflictResolution is a no-op with no conflicts', () async {
    await File('${dir.path}/a.txt').writeAsString('base\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(repoActionsProvider(dir.path)).openConflictResolution();
    expect(c.read(mergeSessionProvider(dir.path)), isNull);
  });

  test(
    'resolveConflicts on a stash session stages and drops the stash',
    () async {
      await makeStashConflict();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));
      final headBefore = (await svc.run([
        'rev-parse',
        'HEAD',
      ], repoPath: dir.path)).out;

      await actions.openConflictResolution();
      var session = c.read(mergeSessionProvider(dir.path))!;
      // Force the dropStashRef path (openConflictResolution leaves it null) and
      // resolve every hunk so the content is clean.
      session = MergeSession(
        branch: session.branch,
        kind: MergeKind.stash,
        dropStashRef: 'stash@{0}',
        files: [
          for (final f in session.files)
            f.hunkIndices.fold(
              f,
              (acc, h) => acc.withResolution(h, Resolution.ours),
            ),
        ],
      );

      await actions.resolveConflicts(session);

      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(await GitReader(svc, dir.path).stashes(), isEmpty); // dropped
      expect(
        (await svc.run(['rev-parse', 'HEAD'], repoPath: dir.path)).out,
        headBefore, // no commit created
      );
    },
  );

  test(
    'abortMerge on a stash session clears conflicts and the session',
    () async {
      await makeStashConflict();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));
      await actions.openConflictResolution();

      await actions.abortMerge();

      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(await GitReader(svc, dir.path).conflictedFiles(), isEmpty);
    },
  );

  test(
    'stashPop conflict opens a stash session that drops on finish',
    () async {
      await primeStash();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(repoActionsProvider(dir.path)).stashPop('stash@{0}');
      final s = c.read(mergeSessionProvider(dir.path));
      expect(s, isNotNull);
      expect(s!.kind, MergeKind.stash);
      expect(s.dropStashRef, 'stash@{0}');
    },
  );

  test('stashApply conflict opens a stash session with no drop', () async {
    await primeStash();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(repoActionsProvider(dir.path)).stashApply('stash@{0}');
    final s = c.read(mergeSessionProvider(dir.path));
    expect(s, isNotNull);
    expect(s!.dropStashRef, isNull);
  });
}
