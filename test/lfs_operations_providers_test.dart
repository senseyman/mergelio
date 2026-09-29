import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/lfs.dart';

const _oid = '482b8673d879f129dbcc30eb80fcf939481fd963bba4e0a7ebcc2df0e9f50c7b';

/// Scripted by the first argument after `lfs` for git-lfs, else by the git
/// subcommand.
class _Git implements GitService {
  final Map<String, GitResult> answers;
  final calls = <List<String>>[];
  final timeouts = <Duration?>[];
  _Git(this.answers);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    timeouts.add(timeout);
    final key = args.first == 'lfs' ? 'lfs ${args[1]}' : args.first;
    return answers[key] ?? const GitResult(1, '', 'unscripted');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _src = LfsSource(repoPath: '/r');
const _lfsRepo = GitResult(0, '.gitattributes\x00', '');
const _tool = GitResult(0, 'git-lfs/3.8.0 (x)\n', '');

ProviderContainer _c(_Git git, {String? hook}) {
  final c = ProviderContainer(
    overrides: [
      gitServiceProvider.overrideWithValue(git),
      lfsHookTextProvider.overrideWith((ref, repo) async => hook),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('lfsReadyProvider', () {
    test('true for an LFS repo with git-lfs installed', () async {
      final git = _Git({'grep': _lfsRepo, 'lfs version': _tool});
      expect(await _c(git).read(lfsReadyProvider(_src).future), isTrue);
    });
    test('false without git-lfs', () async {
      final git = _Git({'grep': _lfsRepo});
      expect(await _c(git).read(lfsReadyProvider(_src).future), isFalse);
    });
    test('false for a repo without LFS, and git-lfs never asked', () async {
      final git = _Git({
        'grep': const GitResult(1, '', ''),
        'lfs version': _tool,
      });
      expect(await _c(git).read(lfsReadyProvider(_src).future), isFalse);
      expect(git.calls.where((c) => c.first == 'lfs'), isEmpty);
    });
  });

  group('lfsPointerFilesProvider', () {
    test('paths still left as pointers', () async {
      final git = _Git({
        'grep': _lfsRepo,
        'lfs version': _tool,
        'lfs ls-files': const GitResult(
          0,
          '$_oid * a.bin\n$_oid - b c.bin\n',
          '',
        ),
      });
      expect(await _c(git).read(lfsPointerFilesProvider(_src).future), {
        'b c.bin',
      });
      final ls = git.calls.indexWhere(
        (c) => c.length > 1 && c[1] == 'ls-files',
      );
      expect(git.calls[ls], ['lfs', 'ls-files', '-l']);
      expect(git.timeouts[ls], lfsReadTimeout);
    });
    test('runs no git-lfs command when not ready', () async {
      final git = _Git({'grep': const GitResult(1, '', '')});
      expect(await _c(git).read(lfsPointerFilesProvider(_src).future), isEmpty);
      expect(git.calls.where((c) => c.first == 'lfs'), isEmpty);
    });
    test('a failing ls-files shows nothing', () async {
      final git = _Git({
        'grep': _lfsRepo,
        'lfs version': _tool,
        'lfs ls-files': const GitResult(2, '', 'boom'),
      });
      expect(await _c(git).read(lfsPointerFilesProvider(_src).future), isEmpty);
    });
    test('recomputes after the generation moves', () async {
      final git = _Git({
        'grep': _lfsRepo,
        'lfs version': _tool,
        'lfs ls-files': const GitResult(0, '', ''),
      });
      final c = _c(git);
      final sub = c.listen(lfsPointerFilesProvider(_src), (_, _) {});
      addTearDown(sub.close);
      await c.read(lfsPointerFilesProvider(_src).future);
      c.read(lfsGenerationProvider('/r').notifier).state++;
      await c.read(lfsPointerFilesProvider(_src).future);
      expect(
        git.calls.where((c) => c.length > 1 && c[1] == 'ls-files'),
        hasLength(2),
      );
    });
  });

  group('lfsPushReadinessProvider', () {
    test('ready when the repo does not use LFS', () async {
      final git = _Git({'grep': const GitResult(1, '', '')});
      expect(
        await _c(git).read(lfsPushReadinessProvider(_src).future),
        LfsPushReadiness.ready,
      );
    });
    test('toolMissing without git-lfs', () async {
      final git = _Git({'grep': _lfsRepo});
      expect(
        await _c(git).read(lfsPushReadinessProvider(_src).future),
        LfsPushReadiness.toolMissing,
      );
    });
    test('hookMissing with no hook, or a hook that is not git-lfs', () async {
      final git = _Git({'grep': _lfsRepo, 'lfs version': _tool});
      expect(
        await _c(git).read(lfsPushReadinessProvider(_src).future),
        LfsPushReadiness.hookMissing,
      );
      expect(
        await _c(
          git,
          hook: '#!/bin/sh\necho mine\n',
        ).read(lfsPushReadinessProvider(_src).future),
        LfsPushReadiness.hookMissing,
      );
    });
    test('ready with the git-lfs hook', () async {
      final git = _Git({'grep': _lfsRepo, 'lfs version': _tool});
      expect(
        await _c(
          git,
          hook: 'git lfs pre-push "\$@"',
        ).read(lfsPushReadinessProvider(_src).future),
        LfsPushReadiness.ready,
      );
    });
  });
}
