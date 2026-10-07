import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';

/// Records the timeout each command was given.
class _TimeoutGit implements GitService {
  final timeouts = <String, Duration?>{};

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    timeouts[args.where((a) => !a.startsWith('-')).join(' ')] = timeout;
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  group('timeouts', () {
    test('a todo with an exec step runs under the long ceiling', () async {
      final git = _TimeoutGit();
      await GitWriter(git, '/repo').rebase('base', 'pick a\nexec make\n');
      expect(git.timeouts['rebase base'], GitWriter.rebaseSequenceTimeout);
    });

    test('a reword is not an exec step the user added', () async {
      final git = _TimeoutGit();
      await GitWriter(git, '/repo').rebase(
        'base',
        buildRebaseTodo([const RebaseStep('a', RebaseAction.reword)]),
      );
      expect(git.timeouts['rebase base'], isNull);
      await GitWriter(git, '/repo').rebase('base', 'pick a\nexec printf hi\n');
      expect(git.timeouts['rebase base'], GitWriter.rebaseSequenceTimeout);
    });

    test('a todo without exec keeps the ordinary default', () async {
      final git = _TimeoutGit();
      await GitWriter(git, '/repo').rebase('base', 'pick a\n');
      expect(git.timeouts['rebase base'], isNull);
    });

    test(
      'continue may run exec steps still queued, so it waits long',
      () async {
        final git = _TimeoutGit();
        await GitWriter(git, '/repo').rebaseContinue();
        expect(
          git.timeouts['rebase --continue'] ?? git.timeouts['rebase'],
          GitWriter.rebaseSequenceTimeout,
        );
      },
    );
  });

  group('against real git', () {
    late Directory dir;
    const svc = SystemGitService();

    Future<void> g(List<String> args) async {
      final r = await svc.run(args, repoPath: dir.path);
      if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }

    Future<String> out(List<String> args) async =>
        (await svc.run(args, repoPath: dir.path)).out;

    Future<String> commit(String file, String msg) async {
      await File('${dir.path}/$file').writeAsString('$msg\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', msg]);
      return out(['rev-parse', 'HEAD']);
    }

    GitWriter writer() => GitWriter(svc, dir.path);

    Future<bool> rebasing() async {
      final p = await out(['rev-parse', '--git-path', 'rebase-merge']);
      return Directory(p.startsWith('/') ? p : '${dir.path}/$p').existsSync();
    }

    late String base, c1, c2;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mergelio_rbexec_');
      await g(['init', '-q', '-b', 'main']);
      await g(['config', 'user.email', 't@example.com']);
      await g(['config', 'user.name', 'Tester']);
      await g(['config', 'commit.gpgsign', 'false']);
      base = await commit('base.txt', 'base');
      c1 = await commit('f1.txt', 'C1');
      c2 = await commit('f2.txt', 'C2');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('an exec step runs between commits', () async {
      await writer().rebase(
        base,
        buildRebaseTodo([
          RebaseStep(c1, RebaseAction.pick),
          const RebaseStep.exec('git log -1 --format=%s > ran.txt', id: 'x'),
          RebaseStep(c2, RebaseAction.pick),
        ]),
      );
      expect(await File('${dir.path}/ran.txt').readAsString(), 'C1\n');
      expect(await rebasing(), isFalse);
    });

    test('a failing exec throws with its output and leaves the rebase '
        'paused', () async {
      Object? error;
      try {
        await writer().rebase(
          base,
          buildRebaseTodo([
            RebaseStep(c1, RebaseAction.pick),
            const RebaseStep.exec('echo tests-broke; exit 3', id: 'x'),
            RebaseStep(c2, RebaseAction.pick),
          ]),
        );
      } on GitException catch (e) {
        error = e;
      }
      expect(error, isA<GitException>());
      final r = (error! as GitException).result!;
      expect('${r.stdout}${r.stderr}', contains('tests-broke'));
      expect(await rebasing(), isTrue);
      final done = await File('${dir.path}/.git/rebase-merge/done')
          .readAsString();
      expect(
        parseRebaseStop(done),
        const RebaseStop.exec('echo tests-broke; exit 3'),
      );
    });

    test('a break stops without failing, mid-rebase', () async {
      await writer().rebase(
        base,
        buildRebaseTodo([
          RebaseStep(c1, RebaseAction.pick),
          const RebaseStep.breakpoint(id: 'b'),
          RebaseStep(c2, RebaseAction.pick),
        ]),
      );
      expect(await rebasing(), isTrue);
      expect(await out(['log', '-1', '--format=%s']), 'C1');
      await writer().rebaseContinue();
      expect(await rebasing(), isFalse);
      expect(await out(['log', '-1', '--format=%s']), 'C2');
    });

    test('update-ref lines move a stacked branch with its commit', () async {
      await g(['branch', 'stacked', c1]);
      // Drop nothing but reword C1 so every sha above the base changes.
      await writer().rebase(
        base,
        buildRebaseTodo(
          [
            RebaseStep(c1, RebaseAction.reword, message: 'C1 again'),
            RebaseStep(c2, RebaseAction.pick),
          ],
          updateRefs: {
            c1: ['stacked'],
          },
        ),
      );
      expect(await out(['log', '-1', '--format=%s', 'stacked']), 'C1 again');
      expect(
        await out(['rev-parse', 'stacked']),
        await out(['rev-parse', 'HEAD~1']),
      );
    });
  });
}
