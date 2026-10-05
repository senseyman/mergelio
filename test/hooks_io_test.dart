@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/hooks.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/hooks.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/repo_actions.dart';

import 'support/hermetic_git.dart';

/// Notes the permissions of the directory each commit's trace is written to,
/// while git is still running and the file is still there.
class _TraceDirSpy extends HermeticGit {
  final modes = <int>[];
  final dirs = <String>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) {
    final trace = environment?['GIT_TRACE2_EVENT'];
    if (trace != null) {
      final parent = File(trace).parent;
      dirs.add(parent.path);
      modes.add(parent.statSync().mode & 0x1ff);
    }
    return super.run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
      stdin: stdin,
    );
  }
}

void main() {
  const git = HermeticGit();
  late Directory dir;
  late String hooks;

  Future<void> g(List<String> args) async {
    final r = await git.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> hook(String name, String body, {bool exec = true}) async {
    final f = File('$hooks/$name');
    await f.writeAsString('#!/bin/sh\n$body\n');
    await Process.run('chmod', [exec ? '+x' : 'a-x', f.path]);
  }

  Future<HookFile> find(String name) async => (await readHookInventory(
    git,
    dir.path,
  )).hooks.firstWhere((h) => h.name == name);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_hooks_');
    dir = Directory(await dir.resolveSymbolicLinks());
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@t']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    hooks = '${dir.path}/.git/hooks';
    await Directory(hooks).create(recursive: true);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('readHookInventory', () {
    test('lists installed, disabled and sample hooks', () async {
      await hook('pre-commit', 'exit 0');
      await hook('commit-msg', 'exit 0', exec: false);
      await File('$hooks/pre-push.sample').writeAsString('#!/bin/sh\n');
      final inv = await readHookInventory(git, dir.path);
      expect(inv.dir, hooks);
      expect(inv.customPath, isNull);
      final states = {for (final h in inv.hooks) h.name: h.state};
      expect(states['pre-commit'], HookState.active);
      expect(states['commit-msg'], HookState.disabled);
      expect(states['pre-push'], HookState.sample);
    });

    test('follows core.hooksPath and spots husky', () async {
      await Directory('${dir.path}/.husky/_').create(recursive: true);
      await g(['config', 'core.hooksPath', '.husky/_']);
      final inv = await readHookInventory(git, dir.path);
      expect(inv.dir, '${dir.path}/.husky/_');
      expect(inv.customPath, '.husky/_');
      expect(inv.manager, HookManager.husky);
    });

    test('a missing hooks directory is an empty list', () async {
      await Directory(hooks).delete(recursive: true);
      final inv = await readHookInventory(git, dir.path);
      expect(inv.hooks, isEmpty);
    });
  });

  group('hook writes', () {
    test('disable then enable flips what git runs', () async {
      await hook('pre-commit', 'exit 0');
      await setHookEnabled(
        hooks,
        'pre-commit',
        enabled: false,
        repoPath: dir.path,
      );
      expect((await find('pre-commit')).state, HookState.disabled);
      await setHookEnabled(
        hooks,
        'pre-commit',
        enabled: true,
        repoPath: dir.path,
      );
      expect((await find('pre-commit')).state, HookState.active);
    });

    test('writing keeps the hook enabled', () async {
      await hook('pre-commit', 'exit 0');
      await writeHook(
        hooks,
        'pre-commit',
        '#!/bin/sh\nexit 1\n',
        repoPath: dir.path,
      );
      expect(
        await File('$hooks/pre-commit').readAsString(),
        contains('exit 1'),
      );
      expect((await find('pre-commit')).state, HookState.active);
    });

    test('installing a sample copies it and makes it executable', () async {
      await File('$hooks/pre-rebase.sample')
          .writeAsString('#!/bin/sh\nexit 0\n');
      await installSample(hooks, 'pre-rebase', repoPath: dir.path);
      final h = await find('pre-rebase');
      expect(h.state, HookState.active);
    });

    test('installing a sample never replaces a hook', () async {
      await hook('pre-rebase', 'echo mine');
      await File('$hooks/pre-rebase.sample').writeAsString('#!/bin/sh\n');
      await expectLater(
        installSample(hooks, 'pre-rebase', repoPath: dir.path),
        throwsA(
          isA<HookWriteException>().having(
            (e) => e.failure,
            'failure',
            HookWriteFailure.alreadyExists,
          ),
        ),
      );
      expect(await File('$hooks/pre-rebase').readAsString(), contains('mine'));
    });

    test('a hook symlinked outside the repository is refused', () async {
      final outside = await Directory.systemTemp.createTemp('mergelio_out_');
      addTearDown(() => outside.delete(recursive: true));
      final target = File('${outside.path}/evil')..writeAsStringSync('x');
      await Link('$hooks/pre-commit').create(target.path);
      await expectLater(
        writeHook(hooks, 'pre-commit', 'y', repoPath: dir.path),
        throwsA(
          isA<HookWriteException>().having(
            (e) => e.failure,
            'failure',
            HookWriteFailure.outsideRepository,
          ),
        ),
      );
      expect(target.readAsStringSync(), 'x');
    });

    test('a hook symlinked into the repository may be edited', () async {
      final script = File('${dir.path}/scripts/pre-commit');
      await script.create(recursive: true);
      await script.writeAsString('old');
      await Link('$hooks/pre-commit').create(script.path);
      await writeHook(hooks, 'pre-commit', 'new', repoPath: dir.path);
      expect(await script.readAsString(), 'new');
    });

    test(
      'a symlinked hook is listed as linked and cannot be toggled',
      () async {
        final script = File('${dir.path}/scripts/pre-commit');
        await script.create(recursive: true);
        await script.writeAsString('#!/bin/sh\n');
        await Process.run('chmod', ['+x', script.path]);
        await Link('$hooks/pre-commit').create(script.path);
        final h = await find('pre-commit');
        expect(h.isLink, isTrue);
        expect(h.state, HookState.active);
        await expectLater(
          setHookEnabled(
            hooks,
            'pre-commit',
            enabled: false,
            repoPath: dir.path,
          ),
          throwsA(
            isA<HookWriteException>().having(
              (e) => e.failure,
              'failure',
              HookWriteFailure.linked,
            ),
          ),
        );
        // The tracked script keeps its mode: toggling here would have shown up
        // as a change in the working tree.
        expect((await script.stat()).mode & 0x40, isNot(0));
      },
    );

    test('toggling a missing hook names the failure', () async {
      await expectLater(
        setHookEnabled(hooks, 'pre-commit', enabled: true, repoPath: dir.path),
        throwsA(
          isA<HookWriteException>().having(
            (e) => e.failure,
            'failure',
            HookWriteFailure.notFound,
          ),
        ),
      );
    });
  });

  group('hookInventoryProvider', () {
    test('picks up a hook added outside the app while watched', () async {
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(hookInventoryProvider(dir.path), (_, _) {});
      addTearDown(sub.close);
      await container.read(hookInventoryProvider(dir.path).future);

      // git init leaves pre-commit.sample behind, so the hook is already
      // listed — as a sample — before the real one is written.
      HookState? state() => container
          .read(hookInventoryProvider(dir.path))
          .valueOrNull
          ?.hooks
          .where((h) => h.name == 'pre-commit')
          .firstOrNull
          ?.state;
      expect(state(), HookState.sample);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      await hook('pre-commit', 'exit 0');
      while (state() != HookState.active && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(state(), HookState.active);
    });
  });

  group('HookActions', () {
    test('a refused write comes back as the failure, not a toast', () async {
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(container.dispose);
      final failure = await container
          .read(hookActionsProvider(dir.path))
          .setEnabled(hooks, 'pre-commit', enabled: true);
      expect(failure?.failure, HookWriteFailure.notFound);
      expect(container.read(toastProvider), isEmpty);
    });
  });

  group('commit and hooks', () {
    setUp(() async {
      await File('${dir.path}/a.txt').writeAsString('a\n');
      await g(['add', 'a.txt']);
    });

    test('a rejecting pre-commit hook is named', () async {
      await hook('pre-commit', 'echo "lint: 3 problems" >&2; exit 1');
      final writer = GitWriter(git, dir.path);
      await expectLater(
        writer.commit('msg'),
        throwsA(
          isA<HookRejectedException>()
              .having((e) => e.hook, 'hook', 'pre-commit')
              .having(
                (e) => e.result?.err,
                'err',
                contains('lint: 3 problems'),
              ),
        ),
      );
    });

    test('a rejecting commit-msg hook is named', () async {
      await hook('commit-msg', 'echo "bad subject" >&2; exit 1');
      final writer = GitWriter(git, dir.path);
      await expectLater(
        writer.commit('msg'),
        throwsA(
          isA<HookRejectedException>().having(
            (e) => e.hook,
            'hook',
            'commit-msg',
          ),
        ),
      );
    });

    test('a disabled hook leaves no hint in the transcript', () async {
      await hook('pre-commit', 'exit 0', exec: false);
      await hook('commit-msg', 'echo nope >&2; exit 1');
      final writer = GitWriter(git, dir.path);
      await expectLater(
        writer.commit('msg'),
        throwsA(
          isA<HookRejectedException>().having(
            (e) => e.result?.err,
            'err',
            isNot(contains('hint:')),
          ),
        ),
      );
    });

    test(
      'the trace, which holds the message, is private to the user',
      () async {
        final spy = _TraceDirSpy();
        await GitWriter(spy, dir.path).commit('msg');
        expect(spy.modes, hasLength(1));
        expect(spy.modes.single & 0x3f, 0, reason: 'no group/other access');
        // macOS gives each user a private temp dir already; /tmp on Linux is
        // shared, so the trace needs a directory of its own on every host.
        expect(p.equals(spy.dirs.single, Directory.systemTemp.path), isFalse);
        expect(
          Directory(spy.dirs.single).existsSync(),
          isFalse,
          reason: 'removed after the commit',
        );
      },
    );

    test('noVerify skips the hooks', () async {
      await hook('pre-commit', 'exit 1');
      await hook('commit-msg', 'exit 1');
      await GitWriter(git, dir.path).commit('msg', noVerify: true);
      final log = await git.run(['log', '--format=%s'], repoPath: dir.path);
      expect(log.out, 'msg');
    });

    test('a failure no hook caused is a plain GitException', () async {
      await g(['rm', '-q', '--cached', 'a.txt']);
      await expectLater(
        GitWriter(git, dir.path).commit('msg'),
        throwsA(
          isA<GitException>().having(
            (e) => e,
            'type',
            isNot(isA<HookRejectedException>()),
          ),
        ),
      );
    });

    group('older commits and other commands', () {
      late ProviderContainer container;

      setUp(() {
        container = ProviderContainer(
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            profilesProvider.overrideWith(
              (ref) => ProfilesController(
                InMemoryKeyValueStore(),
                const ProfilesState(),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
      });

      Future<String> out(List<String> args) async =>
          (await git.run(args, repoPath: dir.path)).out;

      test('noVerify carries into rewording an older commit', () async {
        await g(['commit', '-q', '-m', 'first']);
        final first = await out(['rev-parse', 'HEAD']);
        await File('${dir.path}/b.txt').writeAsString('b\n');
        await g(['add', 'b.txt']);
        await g(['commit', '-q', '-m', 'second']);
        await hook('commit-msg', 'exit 1');
        await container
            .read(repoActionsProvider(dir.path))
            .rewordCommit(first, 'first, reworded', noVerify: true);
        expect(await out(['log', '--format=%s']), 'second\nfirst, reworded');
      });

      test('a hook refusing cherry-pick --continue is named', () async {
        await g(['commit', '-q', '-m', 'base']);
        await g(['checkout', '-q', '-b', 'side']);
        await File('${dir.path}/a.txt').writeAsString('side\n');
        await g(['commit', '-q', '-am', 'side']);
        await g(['checkout', '-q', 'main']);
        await File('${dir.path}/a.txt').writeAsString('main\n');
        await g(['commit', '-q', '-am', 'main']);
        await git.run(['cherry-pick', 'side'], repoPath: dir.path);
        await File('${dir.path}/a.txt').writeAsString('resolved\n');
        await g(['add', 'a.txt']);
        await hook('pre-commit', 'echo "lint" >&2; exit 1');
        await expectLater(
          GitWriter(git, dir.path).cherryPickContinue(),
          throwsA(
            isA<HookRejectedException>().having(
              (e) => e.hook,
              'hook',
              'pre-commit',
            ),
          ),
        );
      });

      test('a hook refusing a merge is named in the toast', () async {
        await g(['commit', '-q', '-m', 'base']);
        await g(['checkout', '-q', '-b', 'other']);
        await File('${dir.path}/o.txt').writeAsString('o\n');
        await g(['add', 'o.txt']);
        await g(['commit', '-q', '-m', 'o']);
        await g(['checkout', '-q', 'main']);
        await File('${dir.path}/m.txt').writeAsString('m\n');
        await g(['add', 'm.txt']);
        await g(['commit', '-q', '-m', 'm']);
        await hook(
          'pre-merge-commit',
          'echo "no merges on Friday" >&2; exit 1',
        );
        await container.read(repoActionsProvider(dir.path)).merge('other');
        final toast = container.read(toastProvider).single;
        expect(toast.title, 'The pre-merge-commit hook stopped Merge');
        expect(toast.description, contains('no merges on Friday'));
      });
    });

    group('rewording HEAD', () {
      setUp(() async {
        await g(['commit', '-q', '-m', 'first']);
        await hook('commit-msg', 'echo "needs a ticket" >&2; exit 1');
      });

      test('the writer names the hook that refused it', () async {
        await expectLater(
          GitWriter(git, dir.path).amendMessage('second'),
          throwsA(
            isA<HookRejectedException>()
                .having((e) => e.hook, 'hook', 'commit-msg')
                .having(
                  (e) => e.result?.err,
                  'err',
                  contains('needs a ticket'),
                ),
          ),
        );
      });

      test('noVerify gets the reword past the hook', () async {
        await GitWriter(git, dir.path).amendMessage('second', noVerify: true);
        final log = await git.run([
          'log',
          '-1',
          '--format=%s',
        ], repoPath: dir.path);
        expect(log.out, 'second');
      });

      test('RepoActions hands the rejection back without a toast', () async {
        final container = ProviderContainer(
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            profilesProvider.overrideWith(
              (ref) => ProfilesController(
                InMemoryKeyValueStore(),
                const ProfilesState(),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final actions = container.read(repoActionsProvider(dir.path));
        final head = (await git.run([
          'rev-parse',
          'HEAD',
        ], repoPath: dir.path)).out;
        final rejection = await actions.rewordCommit(head, 'second');
        expect(rejection?.hook, 'commit-msg');
        expect(container.read(toastProvider), isEmpty);

        final retry = await actions.rewordCommit(
          head,
          'second',
          noVerify: true,
        );
        expect(retry, isNull);
        final log = await git.run([
          'log',
          '-1',
          '--format=%s',
        ], repoPath: dir.path);
        expect(log.out, 'second');
      });
    });

    group('RepoActions.commit', () {
      late ProviderContainer container;

      setUp(() {
        container = ProviderContainer(
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            profilesProvider.overrideWith(
              (ref) => ProfilesController(
                InMemoryKeyValueStore(),
                const ProfilesState(),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
      });

      test('reports success', () async {
        final outcome = await container
            .read(repoActionsProvider(dir.path))
            .commit('msg');
        expect(outcome.committed, isTrue);
        expect(outcome.rejection, isNull);
      });

      test('hands a hook rejection back instead of toasting it', () async {
        await hook('pre-commit', 'echo nope >&2; exit 1');
        final outcome = await container
            .read(repoActionsProvider(dir.path))
            .commit('msg');
        expect(outcome.committed, isFalse);
        expect(outcome.rejection?.hook, 'pre-commit');
        expect(container.read(toastProvider), isEmpty);
      });

      test('any other failure is not reported as committed', () async {
        await g(['rm', '-q', '--cached', 'a.txt']);
        final outcome = await container
            .read(repoActionsProvider(dir.path))
            .commit('msg');
        expect(outcome.committed, isFalse);
        expect(outcome.rejection, isNull);
        expect(container.read(toastProvider), isNotEmpty);
      });

      test('noVerify reaches git', () async {
        await hook('pre-commit', 'exit 1');
        final outcome = await container
            .read(repoActionsProvider(dir.path))
            .commit('msg', noVerify: true);
        expect(outcome.committed, isTrue);
      });
    });
  });
}
