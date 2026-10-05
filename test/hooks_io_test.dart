@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/hooks.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Real git with the host's global and system config shut out, so a
/// developer's own core.hooksPath cannot change what these tests see.
class _HermeticGit implements GitService {
  const _HermeticGit();

  static const _inner = SystemGitService();
  static const _isolation = {
    'GIT_CONFIG_GLOBAL': '/dev/null',
    'GIT_CONFIG_NOSYSTEM': '1',
  };

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => _inner.run(
    args,
    repoPath: repoPath,
    timeout: timeout,
    environment: {...?environment, ..._isolation},
    cancel: cancel,
    stdin: stdin,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const git = _HermeticGit();
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
      expect(h.hasSample, isTrue);
    });

    test('installing a sample never replaces a hook', () async {
      await hook('pre-rebase', 'echo mine');
      await File('$hooks/pre-rebase.sample').writeAsString('#!/bin/sh\n');
      await expectLater(
        installSample(hooks, 'pre-rebase', repoPath: dir.path),
        throwsA(isA<FileSystemException>()),
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
        throwsA(isA<FileSystemException>()),
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
