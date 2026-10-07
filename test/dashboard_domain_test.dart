import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/dashboard.dart';

/// Joins porcelain v2 records the way `-z` emits them.
String _z(List<String> records) => '${records.join('\x00')}\x00';

RepoSnapshot _snap({
  String? branch = 'main',
  bool detached = false,
  String? upstream = 'origin/main',
  bool upstreamGone = false,
  int ahead = 0,
  int behind = 0,
  int changed = 0,
  int conflicted = 0,
  int untracked = 0,
  RepoOp? op,
}) => RepoSnapshot(
  summary: StatusSummary(
    branch: branch,
    detached: detached,
    upstream: upstream,
    upstreamGone: upstreamGone,
    ahead: ahead,
    behind: behind,
    changed: changed,
    conflicted: conflicted,
    untracked: untracked,
  ),
  stashCount: 0,
  op: op,
);

void main() {
  group('parseStatusSummary', () {
    test('reads branch, upstream and ahead/behind', () {
      final s = parseStatusSummary(
        _z([
          '# branch.oid 1234567890abcdef1234567890abcdef12345678',
          '# branch.head main',
          '# branch.upstream origin/main',
          '# branch.ab +2 -3',
        ]),
      );
      expect(s.branch, 'main');
      expect(s.detached, isFalse);
      expect(s.unborn, isFalse);
      expect(s.upstream, 'origin/main');
      expect(s.upstreamGone, isFalse);
      expect(s.ahead, 2);
      expect(s.behind, 3);
      expect(s.changed, 0);
      expect(s.untracked, 0);
    });

    test('an upstream with no ab line is gone from the remote', () {
      final s = parseStatusSummary(
        _z([
          '# branch.oid 1234567890abcdef1234567890abcdef12345678',
          '# branch.head feature',
          '# branch.upstream origin/feature',
        ]),
      );
      expect(s.upstream, 'origin/feature');
      expect(s.upstreamGone, isTrue);
      expect(s.ahead, 0);
      expect(s.behind, 0);
    });

    test('no upstream line means the branch tracks nothing', () {
      final s = parseStatusSummary(
        _z([
          '# branch.oid 1234567890abcdef1234567890abcdef12345678',
          '# branch.head topic',
        ]),
      );
      expect(s.upstream, isNull);
      expect(s.upstreamGone, isFalse);
    });

    test('detached HEAD has no branch', () {
      final s = parseStatusSummary(
        _z([
          '# branch.oid 1234567890abcdef1234567890abcdef12345678',
          '# branch.head (detached)',
        ]),
      );
      expect(s.detached, isTrue);
      expect(s.branch, isNull);
    });

    test('an initial oid is an unborn branch', () {
      final s = parseStatusSummary(
        _z(['# branch.oid (initial)', '# branch.head main']),
      );
      expect(s.unborn, isTrue);
      expect(s.branch, 'main');
    });

    test('counts changed, conflicted and untracked entries apart', () {
      final s = parseStatusSummary(
        _z([
          '# branch.oid 1234567890abcdef1234567890abcdef12345678',
          '# branch.head main',
          '1 .M N... 100644 100644 100644 aaa bbb a.txt',
          '1 M. N... 100644 100644 100644 aaa bbb dir/with space.txt',
          // A rename carries its original path as the next record, which must
          // not be counted as a second entry.
          '2 R. N... 100644 100644 100644 aaa bbb R100 new.txt',
          // A name that itself looks like a record type.
          '1 old.txt',
          'u UU N... 100644 100644 100644 100644 aaa bbb ccc c.txt',
          '? new1.txt',
          '? new2.txt',
          '! ignored.log',
        ]),
      );
      expect(s.changed, 3);
      expect(s.conflicted, 1);
      expect(s.untracked, 2);
    });

    test('a malformed ab line is tolerated, not thrown', () {
      final s = parseStatusSummary(
        _z([
          '# branch.oid 1234567890abcdef1234567890abcdef12345678',
          '# branch.head main',
          '# branch.upstream origin/main',
          // A doubled space, and a segment with no sign at all.
          '# branch.ab +2  -3 x',
        ]),
      );
      expect(s.ahead, 2);
      expect(s.behind, 3);
      expect(s.upstreamGone, isFalse);
    });

    test('an empty answer is a clean, unknown state rather than a crash', () {
      final s = parseStatusSummary('');
      expect(s.branch, isNull);
      expect(s.changed, 0);
    });
  });

  group('opFromStateFiles', () {
    test('nothing present is no operation', () {
      expect(opFromStateFiles(const {}), isNull);
    });

    test('a rebase wins over the cherry-pick head it leaves beside it', () {
      expect(
        opFromStateFiles(const {'rebase-merge', 'CHERRY_PICK_HEAD'}),
        RepoOp.rebase,
      );
    });

    test('rebase-apply with an applying marker is git am', () {
      expect(
        opFromStateFiles(const {'rebase-apply', 'rebase-apply/applying'}),
        RepoOp.am,
      );
      expect(opFromStateFiles(const {'rebase-apply'}), RepoOp.rebase);
    });

    test('maps each sequencer head to its operation', () {
      expect(opFromStateFiles(const {'MERGE_HEAD'}), RepoOp.merge);
      expect(opFromStateFiles(const {'CHERRY_PICK_HEAD'}), RepoOp.cherryPick);
      expect(opFromStateFiles(const {'REVERT_HEAD'}), RepoOp.revert);
      expect(opFromStateFiles(const {'BISECT_LOG'}), RepoOp.bisect);
    });

    test('a merge outranks a bisect running underneath it', () {
      expect(
        opFromStateFiles(const {'MERGE_HEAD', 'BISECT_LOG'}),
        RepoOp.merge,
      );
    });
  });

  group('pullSkipReason', () {
    test('behind only, clean, tracked: eligible', () {
      expect(pullSkipReason(_snap(behind: 2)), isNull);
    });

    test('untracked files do not block a fast-forward', () {
      expect(pullSkipReason(_snap(behind: 2, untracked: 4)), isNull);
    });

    test('an unreadable repository is skipped first', () {
      expect(pullSkipReason(null), PullSkip.unreadable);
    });

    test('an operation in progress is reported before anything else', () {
      expect(
        pullSkipReason(_snap(behind: 1, changed: 3, op: RepoOp.merge)),
        PullSkip.operation,
      );
    });

    test('detached HEAD has nothing to pull into', () {
      expect(
        pullSkipReason(_snap(branch: null, detached: true, upstream: null)),
        PullSkip.detached,
      );
    });

    test('no upstream and upstream gone are told apart', () {
      expect(pullSkipReason(_snap(upstream: null)), PullSkip.noUpstream);
      expect(
        pullSkipReason(_snap(upstreamGone: true, behind: 0)),
        PullSkip.upstreamGone,
      );
    });

    test('tracked changes or conflicts make it dirty', () {
      expect(pullSkipReason(_snap(behind: 1, changed: 1)), PullSkip.dirty);
      expect(pullSkipReason(_snap(behind: 1, conflicted: 1)), PullSkip.dirty);
    });

    test('ahead and behind at once cannot fast-forward', () {
      expect(pullSkipReason(_snap(ahead: 1, behind: 1)), PullSkip.diverged);
    });

    test('nothing to pull is up to date, even when ahead', () {
      expect(pullSkipReason(_snap()), PullSkip.upToDate);
      expect(pullSkipReason(_snap(ahead: 3)), PullSkip.upToDate);
    });
  });

  group('countReflogEntries', () {
    test('one entry per non-empty line', () {
      expect(countReflogEntries('a b c\nd e f\n'), 2);
      expect(countReflogEntries(''), 0);
      expect(countReflogEntries('\n\n'), 0);
    });
  });
}
