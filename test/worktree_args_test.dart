import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

class _CapturingGit implements GitService {
  final List<List<String>> calls = [];
  String stdout;
  String stderr;
  int exitCode;
  _CapturingGit({this.stdout = '', this.stderr = '', this.exitCode = 0});

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    return GitResult(exitCode, stdout, exitCode == 0 ? stderr : 'boom');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  test('reader asks git for porcelain output and parses it', () async {
    final git = _CapturingGit(
      stdout:
          'worktree /r\nHEAD 1111111111111111111111111111111111111111\n'
          'branch refs/heads/main\n\n',
    );
    final list = await GitReader(git, '/r').worktrees();
    expect(git.calls.single, ['worktree', 'list', '--porcelain']);
    expect(list.single.branch, 'main');
  });

  test('reader returns empty when git fails rather than throwing', () async {
    final git = _CapturingGit(exitCode: 128);
    expect(await GitReader(git, '/r').worktrees(), isEmpty);
  });

  group('writer argv', () {
    late _CapturingGit git;
    late GitWriter w;
    setUp(() {
      git = _CapturingGit();
      w = GitWriter(git, '/r');
    });

    test('add with a new branch from a start point', () async {
      await w.addWorktree('/r-x', newBranch: 'feat/x', startPoint: 'main');
      expect(git.calls.single, [
        'worktree',
        'add',
        '-b',
        'feat/x',
        '/r-x',
        'main',
      ]);
    });

    test('add attaching an existing branch', () async {
      await w.addWorktree('/r-x', existingBranch: 'hotfix');
      expect(git.calls.single, ['worktree', 'add', '/r-x', 'hotfix']);
    });

    test('add detached at a ref', () async {
      await w.addWorktree('/r-x', detach: true, startPoint: 'HEAD~2');
      expect(git.calls.single, [
        'worktree',
        'add',
        '--detach',
        '/r-x',
        'HEAD~2',
      ]);
    });

    test('remove, plain and forced', () async {
      await w.removeWorktree('/r-x');
      expect(git.calls.last, ['worktree', 'remove', '/r-x']);
      await w.removeWorktree('/r-x', force: true);
      expect(git.calls.last, ['worktree', 'remove', '--force', '/r-x']);
    });

    test('move', () async {
      await w.moveWorktree('/r-x', '/r-y');
      expect(git.calls.single, ['worktree', 'move', '/r-x', '/r-y']);
    });

    test('lock with and without a reason, and unlock', () async {
      await w.lockWorktree('/r-x');
      expect(git.calls.last, ['worktree', 'lock', '/r-x']);
      await w.lockWorktree('/r-x', reason: 'on usb');
      expect(git.calls.last, [
        'worktree',
        'lock',
        '--reason',
        'on usb',
        '/r-x',
      ]);
      await w.unlockWorktree('/r-x');
      expect(git.calls.last, ['worktree', 'unlock', '/r-x']);
    });

    test('prune, real and dry run, returns git report', () async {
      // `git worktree prune -v` writes its report to stderr, not stdout,
      // even on success.
      final pruneGit = _CapturingGit(
        stderr: 'Removing worktrees/gone: gitdir file points nowhere\n',
      );
      final pruneWriter = GitWriter(pruneGit, '/r');
      final report = await pruneWriter.pruneWorktrees(dryRun: true);
      expect(pruneGit.calls.last, ['worktree', 'prune', '-v', '--dry-run']);
      expect(report, contains('Removing worktrees/gone'));
      await pruneWriter.pruneWorktrees();
      expect(pruneGit.calls.last, ['worktree', 'prune', '-v']);
    });

    test('checkout passes --ignore-other-worktrees only when asked', () async {
      await w.checkout('feat/x');
      expect(git.calls.last, isNot(contains('--ignore-other-worktrees')));
      await w.checkout('feat/x', ignoreOtherWorktrees: true);
      expect(git.calls.last, contains('--ignore-other-worktrees'));
    });

    test('a failing call throws GitException', () async {
      final bad = _CapturingGit(exitCode: 1);
      expect(
        () => GitWriter(bad, '/r').removeWorktree('/r-x'),
        throwsA(isA<GitException>()),
      );
    });
  });
}
