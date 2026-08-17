import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/worktree.dart';

void main() {
  test('parses main plus two linked worktrees', () {
    const raw = '''
worktree /home/u/repo
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main

worktree /home/u/repo-login
HEAD 2222222222222222222222222222222222222222
branch refs/heads/feat/login

worktree /home/u/repo-hot
HEAD 3333333333333333333333333333333333333333
branch refs/heads/hotfix
''';
    final w = parseWorktreeList(raw);
    expect(w.length, 3);
    expect(w[0].path, '/home/u/repo');
    expect(w[0].branch, 'main');
    expect(w[0].kind, WorktreeKind.main);
    expect(w[1].branch, 'feat/login');
    expect(w[1].kind, WorktreeKind.linked);
    expect(w[2].kind, WorktreeKind.linked);
  });

  test('detached worktree has no branch', () {
    const raw = '''
worktree /home/u/repo
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main

worktree /home/u/repo-det
HEAD abcdef1234567890abcdef1234567890abcdef12
detached
''';
    final w = parseWorktreeList(raw);
    expect(w[1].detached, isTrue);
    expect(w[1].branch, isNull);
    expect(w[1].shortHead, 'abcdef1');
  });

  test('bare main entry has no head and kind bare', () {
    const raw = '''
worktree /home/u/repo.git
bare

worktree /home/u/repo-work
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main
''';
    final w = parseWorktreeList(raw);
    expect(w[0].kind, WorktreeKind.bare);
    expect(w[0].head, isNull);
    expect(w[1].kind, WorktreeKind.linked);
  });

  test('locked with and without a reason', () {
    const raw = '''
worktree /home/u/a
HEAD 1111111111111111111111111111111111111111
branch refs/heads/a
locked

worktree /home/u/b
HEAD 2222222222222222222222222222222222222222
branch refs/heads/b
locked on a removable drive
''';
    final w = parseWorktreeList(raw);
    expect(w[0].locked, isTrue);
    expect(w[0].lockReason, isNull);
    expect(w[1].locked, isTrue);
    expect(w[1].lockReason, 'on a removable drive');
  });

  test('prunable carries its reason', () {
    const raw = '''
worktree /home/u/a
HEAD 1111111111111111111111111111111111111111
branch refs/heads/a

worktree /home/u/gone
HEAD 2222222222222222222222222222222222222222
branch refs/heads/gone
prunable gitdir file points to non-existent location
''';
    final w = parseWorktreeList(raw);
    expect(w[1].prunable, isTrue);
    expect(w[1].prunableReason, 'gitdir file points to non-existent location');
  });

  test('tolerates CRLF, trailing blank lines and paths with spaces', () {
    const raw =
        'worktree /home/u/my repo\r\n'
        'HEAD 1111111111111111111111111111111111111111\r\n'
        'branch refs/heads/feature/ümlaut\r\n'
        '\r\n\r\n';
    final w = parseWorktreeList(raw);
    expect(w.length, 1);
    expect(w[0].path, '/home/u/my repo');
    expect(w[0].branch, 'feature/ümlaut');
  });

  test('empty input yields an empty list', () {
    expect(parseWorktreeList(''), isEmpty);
    expect(parseWorktreeList('\n\n'), isEmpty);
  });

  test('is const-constructible with defaults', () {
    const w = Worktree(path: '/home/u/repo', branch: 'main');
    expect(w.detached, isFalse);
    expect(w.locked, isFalse);
    expect(w.prunable, isFalse);
    expect(w.kind, WorktreeKind.linked);
    expect(w.head, isNull);
  });

  test('shortHead tolerates a head shorter than 7 characters', () {
    const w = Worktree(path: '/r', head: 'abc');
    expect(w.shortHead, 'abc');
  });

  group('helpers', () {
    const main0 = Worktree(
      path: '/home/u/repo',
      branch: 'main',
      kind: WorktreeKind.main,
    );
    const login = Worktree(path: '/home/u/repo-login', branch: 'feat/login');
    const det = Worktree(path: '/home/u/repo-det', detached: true);
    const all = [main0, login, det];

    test('worktreeHolding finds the holder of a branch', () {
      expect(worktreeHolding(all, 'feat/login')?.path, '/home/u/repo-login');
      expect(worktreeHolding(all, 'main')?.path, '/home/u/repo');
      expect(worktreeHolding(all, 'nobody'), isNull);
    });

    test('suggestWorktreePath proposes a sibling directory', () {
      expect(
        suggestWorktreePath('/home/u/repo', 'feat/login'),
        '/home/u/repo-feat-login',
      );
      expect(
        suggestWorktreePath('/home/u/repo/', 'hotfix'),
        '/home/u/repo-hotfix',
      );
      expect(
        suggestWorktreePath(r'C:\code\repo', 'feat/x'),
        r'C:\code\repo-feat-x',
      );
    });

    test('validateWorktreeDestination rejects the bad cases', () {
      String? v(String dest) => validateWorktreeDestination(
        destination: dest,
        repoPath: '/home/u/repo',
        existing: all,
      );
      expect(v(''), isNotNull);
      expect(v("/home/u/repo"), isNotNull, reason: "the repository itself");
      expect(v('/home/u/repo/inside'), isNotNull, reason: 'inside the repo');
      expect(v('/home/u/repo-login'), isNotNull, reason: 'already a worktree');
      expect(v('/home/u/repo-new'), isNull);
    });

    test(
      'a destination inside a symlinked repository is still rejected',
      () async {
        // The destination does not exist yet, so it cannot be resolved on its
        // own; the repository is reached through a symlink, so its key does
        // not match the destination's spelling textually. Keying the
        // destination against its deepest existing ancestor is what makes the
        // two comparable.
        final real = await Directory.systemTemp.createTemp('mergelio_dest_');
        final repo = Directory('${real.path}/repo')..createSync();
        final link = Link('${real.path}_link');
        await link.create(real.path);
        final repoViaLink = '${link.path}/repo';
        try {
          expect(
            validateWorktreeDestination(
              destination: '$repoViaLink/inside',
              repoPath: repo.path,
              existing: const [],
            ),
            isNotNull,
            reason: 'a not-yet-created directory inside the repo',
          );
          expect(
            validateWorktreeDestination(
              destination: '${link.path}/repo-feature',
              repoPath: repo.path,
              existing: const [],
            ),
            isNull,
            reason: 'a not-yet-created sibling outside the repo',
          );
        } finally {
          await link.delete();
          await real.delete(recursive: true);
        }
      },
    );

    test('validateNewBranchName rejects names git would refuse', () {
      expect(validateNewBranchName(''), isNotNull);
      expect(validateNewBranchName('has space'), isNotNull);
      expect(validateNewBranchName('a..b'), isNotNull);
      expect(validateNewBranchName('-leading'), isNotNull);
      expect(validateNewBranchName('ends/'), isNotNull);
      expect(validateNewBranchName('feat/login'), isNull);
    });

    test('validateNewBranchName rejects the reflog and lock spellings', () {
      // check-ref-format refuses all of these; catching them here spares the
      // user a round trip to git for a name it was never going to accept.
      expect(validateNewBranchName('feat@{1}'), isNotNull);
      expect(validateNewBranchName('HEAD'), isNotNull);
      expect(validateNewBranchName('feat.lock'), isNotNull);
      expect(validateNewBranchName('feat/.hidden'), isNotNull);
      expect(validateNewBranchName('.leading'), isNotNull);
      expect(validateNewBranchName('a\u0007b'), isNotNull);
      // An @ that is not a reflog spelling is a legal branch name.
      expect(validateNewBranchName('feat@home'), isNull);
      expect(validateNewBranchName('release-1.0'), isNull);
    });
  });
}
