import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/review.dart';
import 'package:mergelio/domain/git/worktree.dart';

PullRequest _pr(int n, String target) => PullRequest(
  number: n,
  title: 't$n',
  state: PullRequestState.open,
  author: const ForgeUser(login: 'u'),
  sourceBranch: 'feature',
  targetBranch: target,
  headSha: 'abc',
);

void main() {
  group('parseLeftRightCount', () {
    test('left is what only base has, right what only head has', () {
      final c = parseLeftRightCount('3\t5\n');
      expect(c.behind, 3);
      expect(c.ahead, 5);
    });

    test('tolerates spaces between the counts', () {
      final c = parseLeftRightCount('0 12');
      expect(c.behind, 0);
      expect(c.ahead, 12);
    });

    test('rejects output that is not two counts', () {
      expect(() => parseLeftRightCount(''), throwsFormatException);
      expect(() => parseLeftRightCount('7'), throwsFormatException);
      expect(() => parseLeftRightCount('a b'), throwsFormatException);
    });
  });

  group('reviewRange', () {
    test('names the git range each mode reads', () {
      expect(reviewRange('main', 'feature', threeDot: true), 'main...feature');
      expect(reviewRange('main', 'feature', threeDot: false), 'main..feature');
    });
  });

  group('parseReviewFiles', () {
    // Exactly what git 2.x prints for `diff --raw --no-abbrev -z -M` and
    // `diff --numstat -z -M` over an add (binary), delete, mode+content
    // change and a rename with an edit.
    const z = '0000000000000000000000000000000000000000';
    const raw =
        ':000000 100644 $z bdc955b7b2e610ad5a72302b139a2e6cb325519a A\x00bin.dat\x00'
        ':100644 000000 587be6b4c3f93f93c489c0111bba5596147a26cb $z D\x00gone.txt\x00'
        ':100644 100755 28ce6a8b26aa170e1de65536fe8abe1832bd3242 3d3fffbbfd74e37fb6e9ce38b0ef7e97da0f2d3d M\x00mod.txt\x00'
        ':100644 100644 0fdf397db08b5cecda1b6394d4fef7395c1933ba f9d9a0195c5b9c01ef64e2a69d8b9a624f42b8c8 R085\x00keep.txt\x00moved.txt\x00';
    const numstat =
        '-\t-\tbin.dat\x00'
        '0\t1\tgone.txt\x00'
        '1\t0\tmod.txt\x00'
        '1\t0\t\x00keep.txt\x00moved.txt\x00';

    test('reads every change with its counts', () {
      final files = parseReviewFiles(raw: raw, numstat: numstat);
      expect(
        [for (final f in files) (f.change.path, f.change.change)],
        [
          ('bin.dat', GitChange.added),
          ('gone.txt', GitChange.deleted),
          ('mod.txt', GitChange.modified),
          ('moved.txt', GitChange.renamed),
        ],
      );
      expect(files[3].change.origPath, 'keep.txt');
      expect((files[0].binary, files[0].lines), (true, 0));
      expect((files[1].adds, files[1].dels), (0, 1));
      expect((files[3].adds, files[3].dels, files[3].lines), (1, 0, 1));
    });

    test('a file numstat skipped still lists, with no counts', () {
      final files = parseReviewFiles(raw: raw, numstat: '');
      expect(files, hasLength(4));
      expect((files[2].adds, files[2].dels, files[2].binary), (0, 0, false));
    });

    test('the fingerprint follows content and mode, not the path alone', () {
      final a = parseReviewFiles(raw: raw, numstat: numstat);
      final again = parseReviewFiles(raw: raw, numstat: numstat);
      expect(a[2].fingerprint, again[2].fingerprint);
      final edited = parseReviewFiles(
        raw: raw.replaceFirst('3d3fffbb', '3d3fffbc'),
        numstat: numstat,
      );
      expect(edited[2].fingerprint, isNot(a[2].fingerprint));
      final modeOnly = parseReviewFiles(
        raw: raw.replaceFirst(':100644 100755', ':100644 100644'),
        numstat: numstat,
      );
      expect(modeOnly[2].fingerprint, isNot(a[2].fingerprint));
    });

    test('ignores a truncated record', () {
      expect(
        parseReviewFiles(raw: ':100644 100644 a b M', numstat: ''),
        isEmpty,
      );
    });
  });

  group('reviewRefChoices', () {
    test('lists branches, remote branches, tags and linked worktrees', () {
      final choices = reviewRefChoices(
        repoPath: '/repo',
        branches: const [
          Branch(name: 'main', current: true),
          Branch(name: 'feature'),
        ],
        remoteBranches: const [RemoteBranch(remote: 'origin', branch: 'main')],
        tags: const ['v1.0'],
        worktrees: [
          Worktree(path: '/repo', head: 'a' * 40, branch: 'main'),
          Worktree(path: '/wt/hotfix', head: 'b' * 40, branch: 'hotfix'),
          Worktree(path: '/wt/detached', head: 'c' * 40, detached: true),
        ],
      );

      expect(
        [for (final c in choices) (c.kind, c.rev)],
        [
          (RefChoiceKind.branch, 'main'),
          (RefChoiceKind.branch, 'feature'),
          (RefChoiceKind.remote, 'origin/main'),
          (RefChoiceKind.tag, 'v1.0'),
          (RefChoiceKind.worktree, 'hotfix'),
          (RefChoiceKind.worktree, 'c' * 40),
        ],
      );
      expect(choices[4].detail, '/wt/hotfix');
    });

    test(
      'a branch checked out in a worktree is offered once, saying where',
      () {
        final choices = reviewRefChoices(
          repoPath: '/repo',
          branches: const [
            Branch(name: 'main'),
            Branch(name: 'hotfix'),
          ],
          remoteBranches: const [],
          tags: const [],
          worktrees: const [Worktree(path: '/wt/hotfix', branch: 'hotfix')],
        );
        expect(
          [for (final c in choices) (c.kind, c.rev, c.detail)],
          [
            (RefChoiceKind.branch, 'main', null),
            (RefChoiceKind.branch, 'hotfix', '/wt/hotfix'),
          ],
        );
      },
    );

    test('skips a remote HEAD alias and a worktree with no commit', () {
      final choices = reviewRefChoices(
        repoPath: '/repo',
        branches: const [],
        remoteBranches: const [RemoteBranch(remote: 'origin', branch: 'HEAD')],
        tags: const [],
        worktrees: const [Worktree(path: '/wt/new')],
      );
      expect(choices, isEmpty);
    });
  });

  group('prBranchFor', () {
    test('a local branch is its own name', () {
      expect(
        prBranchFor('feature', localBranches: ['feature'], remotes: ['origin']),
        'feature',
      );
    });

    test('a remote branch drops its remote', () {
      expect(
        prBranchFor(
          'origin/feat/x',
          localBranches: const [],
          remotes: ['origin'],
        ),
        'feat/x',
      );
    });

    test('a sha or tag names no branch', () {
      expect(
        prBranchFor('a' * 40, localBranches: ['main'], remotes: ['origin']),
        isNull,
      );
      expect(
        prBranchFor('v1.0', localBranches: ['main'], remotes: ['origin']),
        isNull,
      );
    });
  });

  group('pickPullRequest', () {
    test('prefers the request that targets the base branch', () {
      final pr = pickPullRequest([_pr(1, 'release'), _pr(2, 'main')], 'main');
      expect(pr?.number, 2);
    });

    test('a single request is the answer even against another base', () {
      expect(pickPullRequest([_pr(1, 'release')], 'main')?.number, 1);
    });

    test('several requests and none on base is ambiguous', () {
      expect(pickPullRequest([_pr(1, 'a'), _pr(2, 'b')], 'main'), isNull);
      expect(pickPullRequest(const [], 'main'), isNull);
    });
  });

  group('reviewFileExpanded', () {
    test('open by default, closed once viewed or when huge', () {
      expect(reviewFileExpanded(viewed: false, lineCount: 10), isTrue);
      expect(reviewFileExpanded(viewed: true, lineCount: 10), isFalse);
      expect(
        reviewFileExpanded(viewed: false, lineCount: kReviewLargeDiffLines + 1),
        isFalse,
      );
      expect(
        reviewFileExpanded(viewed: false, lineCount: kReviewLargeDiffLines),
        isTrue,
      );
    });

    test('the reader\'s own choice wins over every default', () {
      expect(
        reviewFileExpanded(choice: true, viewed: true, lineCount: 99999),
        isTrue,
      );
      expect(
        reviewFileExpanded(choice: false, viewed: false, lineCount: 1),
        isFalse,
      );
    });
  });

  group('lineHistoryAnchor', () {
    test('an added or unchanged line is read on head by its new number', () {
      final a = lineHistoryAnchor(
        const DiffLine(type: DiffLineType.add, newNo: 12, text: 'x'),
        path: 'new.txt',
        oldPath: 'old.txt',
        headRev: 'H',
        fromRev: 'B',
      );
      expect((a?.path, a?.line, a?.rev), ('new.txt', 12, 'H'));
      final c = lineHistoryAnchor(
        const DiffLine(
          type: DiffLineType.context,
          oldNo: 3,
          newNo: 4,
          text: 'x',
        ),
        path: 'f',
        headRev: 'H',
        fromRev: 'B',
      );
      expect((c?.line, c?.rev), (4, 'H'));
    });

    test('a removed line is read on the base side, under its old name', () {
      final a = lineHistoryAnchor(
        const DiffLine(type: DiffLineType.del, oldNo: 7, text: 'x'),
        path: 'new.txt',
        oldPath: 'old.txt',
        headRev: 'H',
        fromRev: 'B',
      );
      expect((a?.path, a?.line, a?.rev), ('old.txt', 7, 'B'));
    });

    test('a line with no number has no history to show', () {
      expect(
        lineHistoryAnchor(
          const DiffLine(type: DiffLineType.add, text: 'x'),
          path: 'f',
          headRev: 'H',
          fromRev: 'B',
        ),
        isNull,
      );
    });
  });

  group('defaultReviewSides', () {
    test('reviews the current branch against the usual trunk', () {
      final s = defaultReviewSides(const [
        Branch(name: 'develop'),
        Branch(name: 'main'),
        Branch(name: 'feat', current: true),
      ]);
      expect((s.base, s.head), ('main', 'feat'));
    });

    test('falls back to a remote trunk, then leaves base for the user', () {
      expect(
        defaultReviewSides(
          const [Branch(name: 'feat', current: true)],
          remoteBranches: const [
            RemoteBranch(remote: 'origin', branch: 'master'),
          ],
        ).base,
        'origin/master',
      );
      final s = defaultReviewSides(const [Branch(name: 'x', current: true)]);
      expect((s.base, s.head), (null, 'x'));
    });

    test('on the trunk itself there is no base to suggest', () {
      final s = defaultReviewSides(const [Branch(name: 'main', current: true)]);
      expect((s.base, s.head), (null, 'main'));
    });
  });
}
