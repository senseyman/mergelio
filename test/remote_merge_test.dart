import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/remote_ref.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

void main() {
  group('remote ref parsing', () {
    const remotes = ['origin', 'upstream'];

    test('recognises a remote-tracking ref', () {
      expect(isRemoteRef('origin/main', remotes), isTrue);
      expect(isRemoteRef('upstream/release/1.x', remotes), isTrue);
    });

    test('a local branch is not a remote ref', () {
      expect(isRemoteRef('main', remotes), isFalse);
      expect(isRemoteRef('feature/origin', remotes), isFalse);
      // A local branch may be named after a remote without being one.
      expect(isRemoteRef('origin', remotes), isFalse);
    });

    test('an unknown remote prefix is not a remote ref', () {
      expect(isRemoteRef('fork/main', remotes), isFalse);
    });

    test('splitRemoteRef returns the remote and the branch', () {
      expect(splitRemoteRef('origin/main', remotes), ('origin', 'main'));
      expect(splitRemoteRef('upstream/release/1.x', remotes), (
        'upstream',
        'release/1.x',
      ));
      expect(splitRemoteRef('main', remotes), isNull);
    });

    test('the longest matching remote wins', () {
      // `origin` also prefixes `origin/x`, so a remote literally called
      // `origin/mirror` must not be shadowed by `origin`.
      expect(
        splitRemoteRef('origin/mirror/main', ['origin', 'origin/mirror']),
        ('origin/mirror', 'main'),
      );
    });
  });

  group('mergeIntoRemote', () {
    late Directory origin;
    late Directory work;
    const svc = SystemGitService();

    Future<void> run(Directory d, List<String> args) async {
      final r = await svc.run(args, repoPath: d.path);
      if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }

    Future<String> out(Directory d, List<String> args) async =>
        (await svc.run(args, repoPath: d.path)).stdout.trim();

    setUp(() async {
      origin = await Directory.systemTemp.createTemp('mergelio_origin_');
      await run(origin, ['init', '-q', '-b', 'main']);
      await run(origin, ['config', 'user.email', 't@e.com']);
      await run(origin, ['config', 'user.name', 'T']);
      await run(origin, ['config', 'commit.gpgsign', 'false']);
      await File('${origin.path}/a.txt').writeAsString('base\n');
      await run(origin, ['add', '.']);
      await run(origin, ['commit', '-q', '-m', 'base']);
      // A branch that exists only on the remote.
      await run(origin, ['checkout', '-q', '-b', 'feature']);
      await File('${origin.path}/f.txt').writeAsString('feature\n');
      await run(origin, ['add', '.']);
      await run(origin, ['commit', '-q', '-m', 'feature']);
      await run(origin, ['checkout', '-q', 'main']);

      work = await Directory.systemTemp.createTemp('mergelio_work_');
      await work.delete();
      await run(origin, ['clone', '-q', origin.path, work.path]);
      await run(work, ['config', 'user.email', 't@e.com']);
      await run(work, ['config', 'user.name', 'T']);
      await run(work, ['config', 'commit.gpgsign', 'false']);
      // A local topic branch to merge from.
      await run(work, ['checkout', '-q', '-b', 'topic']);
      await File('${work.path}/t.txt').writeAsString('topic\n');
      await run(work, ['add', '.']);
      await run(work, ['commit', '-q', '-m', 'topic']);
    });

    tearDown(() async {
      for (final d in [origin, work]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });

    test(
      'merging into a remote branch with no local copy creates and uses it',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);

        await c
            .read(repoActionsProvider(work.path))
            .mergeIntoRemote(
              'topic',
              const RemoteBranch(remote: 'origin', branch: 'feature'),
            );

        // Ends up on the local tracking branch, not on a detached HEAD.
        expect(
          await out(work, ['rev-parse', '--abbrev-ref', 'HEAD']),
          'feature',
        );
        expect(
          await out(work, ['rev-parse', '--abbrev-ref', 'feature@{upstream}']),
          'origin/feature',
        );
        // Both sides' files are present, so the merge really happened.
        expect(await File('${work.path}/f.txt').exists(), isTrue);
        expect(await File('${work.path}/t.txt').exists(), isTrue);
      },
    );

    test(
      'merging into a remote branch that has a local copy reuses it',
      () async {
        await run(work, ['branch', 'feature', 'origin/feature']);
        final c = ProviderContainer();
        addTearDown(c.dispose);

        await c
            .read(repoActionsProvider(work.path))
            .mergeIntoRemote(
              'topic',
              const RemoteBranch(
                remote: 'origin',
                branch: 'feature',
                hasLocal: true,
              ),
            );

        expect(
          await out(work, ['rev-parse', '--abbrev-ref', 'HEAD']),
          'feature',
        );
        expect(await File('${work.path}/t.txt').exists(), isTrue);
      },
    );

    test(
      'a stale hasLocal=false still merges into the existing branch',
      () async {
        // The row's RepoData can predate a branch created elsewhere; creating
        // the tracking branch then fails, and falling back must not lose the
        // merge.
        await run(work, ['branch', 'feature', 'origin/feature']);
        final c = ProviderContainer();
        addTearDown(c.dispose);

        await c
            .read(repoActionsProvider(work.path))
            .mergeIntoRemote(
              'topic',
              const RemoteBranch(remote: 'origin', branch: 'feature'),
            );

        expect(
          await out(work, ['rev-parse', '--abbrev-ref', 'HEAD']),
          'feature',
        );
        expect(await File('${work.path}/t.txt').exists(), isTrue);
      },
    );

    test('the switch is not a separate undo entry', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(work.path));

      await actions.mergeIntoRemote(
        'topic',
        const RemoteBranch(remote: 'origin', branch: 'feature'),
      );

      // Undoing once takes the merge back; the gesture must not leave a
      // second entry that would then undo the checkout too.
      await actions.undo();
      expect(await File('${work.path}/f.txt').exists(), isTrue);
      expect(await File('${work.path}/t.txt').exists(), isFalse);
      expect(c.read(undoProvider(work.path)).canUndo, isFalse);
    });

    // Rebasing needs no checkout of the target, so a remote-tracking ref goes
    // straight through the existing entry point.
    test('rebaseOnto replays the source onto a remote-tracking ref', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      await c
          .read(repoActionsProvider(work.path))
          .rebaseOnto('topic', 'origin/feature');

      expect(await out(work, ['rev-parse', '--abbrev-ref', 'HEAD']), 'topic');
      // topic now sits on top of origin/feature, so its file is reachable.
      expect(await File('${work.path}/f.txt').exists(), isTrue);
      expect(await File('${work.path}/t.txt').exists(), isTrue);
    });
  });
}
