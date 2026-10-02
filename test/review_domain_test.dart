import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/review.dart';
import 'package:mergelio/domain/git/worktree.dart';

FileDiff _file(String added, {String path = 'a.txt'}) => FileDiff(
  path: path,
  status: GitChange.modified,
  hunks: [
    DiffHunk(
      header: '@@ -1 +1,2 @@',
      oldStart: 1,
      newStart: 1,
      lines: [
        const DiffLine(
          type: DiffLineType.context,
          oldNo: 1,
          newNo: 1,
          text: 'x',
        ),
        DiffLine(type: DiffLineType.add, newNo: 2, text: added),
      ],
    ),
  ],
);

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

  group('diffFingerprint', () {
    test('is the same for equal content parsed twice', () {
      expect(diffFingerprint(_file('y')), diffFingerprint(_file('y')));
    });

    test('changes when a line changes', () {
      expect(diffFingerprint(_file('y')), isNot(diffFingerprint(_file('z'))));
    });

    test('changes with the path', () {
      expect(
        diffFingerprint(_file('y')),
        isNot(diffFingerprint(_file('y', path: 'b.txt'))),
      );
    });

    test('changes when a line flips between added and removed', () {
      FileDiff one(DiffLineType type) => FileDiff(
        path: 'a',
        status: GitChange.modified,
        hunks: [
          DiffHunk(
            header: '@@',
            oldStart: 1,
            newStart: 1,
            lines: [DiffLine(type: type, text: 'q')],
          ),
        ],
      );
      expect(
        diffFingerprint(one(DiffLineType.add)),
        isNot(diffFingerprint(one(DiffLineType.del))),
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
