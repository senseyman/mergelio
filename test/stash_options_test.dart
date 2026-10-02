import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/stash.dart';

void main() {
  _hunkTests();

  group('stashPushArgs', () {
    test('a bare push stashes everything', () {
      expect(stashPushArgs(const StashPushOptions()), ['stash', 'push']);
    });

    test('carries the message and each flag', () {
      expect(
        stashPushArgs(
          const StashPushOptions(
            message: 'wip',
            keepIndex: true,
            includeUntracked: true,
          ),
        ),
        ['stash', 'push', '--keep-index', '--include-untracked', '-m', 'wip'],
      );
    });

    test('staged-only drops the flags git rejects or ignores beside it', () {
      expect(
        stashPushArgs(
          const StashPushOptions(
            stagedOnly: true,
            keepIndex: true,
            includeUntracked: true,
          ),
        ),
        ['stash', 'push', '--staged'],
      );
    });

    test('exclusions keep the rest of the repo, matched literally', () {
      expect(
        stashPushArgs(const StashPushOptions(exclude: ['a.txt', '*.md'])),
        [
          'stash',
          'push',
          '--',
          ':/',
          ':(exclude,literal)a.txt',
          ':(exclude,literal)*.md',
        ],
      );
    });
  });

  group('stashCandidates', () {
    const staged = WorkingFile(path: 's', index: GitChange.modified);
    const unstaged = WorkingFile(path: 'u', worktree: GitChange.modified);
    const untracked = WorkingFile(path: 'n', worktree: GitChange.untracked);

    test('tracked changes, without untracked files by default', () {
      expect(
        stashCandidates([
          staged,
          unstaged,
          untracked,
        ], const StashPushOptions()),
        [staged, unstaged],
      );
    });

    test('untracked files join when they are included', () {
      expect(
        stashCandidates([
          staged,
          unstaged,
          untracked,
        ], const StashPushOptions(includeUntracked: true)),
        [staged, unstaged, untracked],
      );
    });

    test('staged-only offers just what is in the index', () {
      expect(
        stashCandidates([
          staged,
          unstaged,
          untracked,
        ], const StashPushOptions(stagedOnly: true, includeUntracked: true)),
        [staged],
      );
    });
  });

  group('stashExclusions', () {
    const a = WorkingFile(path: 'a', worktree: GitChange.modified);
    const b = WorkingFile(path: 'b', worktree: GitChange.modified);
    const moved = WorkingFile(
      path: 'new',
      origPath: 'old',
      index: GitChange.renamed,
    );

    test('selecting every candidate excludes nothing', () {
      expect(stashExclusions([a, b], {'a', 'b'}), isEmpty);
    });

    test('an unticked file is excluded', () {
      expect(stashExclusions([a, b], {'b'}), ['a']);
    });

    test('an unticked rename excludes both sides so the move stays whole', () {
      expect(stashExclusions([a, moved], {'a'}), ['old', 'new']);
    });

    test('a ticked rename is not named at all', () {
      expect(stashExclusions([a, moved], {'new'}), ['a']);
    });
  });

  group('stash refs', () {
    test('index is read from the reflog selector', () {
      expect(stashIndexOf('stash@{0}'), 0);
      expect(stashIndexOf('stash@{12}'), 12);
    });

    test('anything else has no index', () {
      expect(stashIndexOf('stash'), isNull);
      expect(stashIndexOf('stash@{x}'), isNull);
      expect(stashIndexOf('refs/stash@{1}'), isNull);
    });

    test('ref is rebuilt from an index', () {
      expect(stashRefAt(3), 'stash@{3}');
    });
  });
}

void _hunkTests() {
  group('canApplyStashHunks', () {
    const hunk = DiffHunk(
      header: '@@ -1 +1 @@',
      oldStart: 1,
      newStart: 1,
      lines: [],
    );

    test('a modified text file can be applied hunk by hunk', () {
      expect(
        canApplyStashHunks(
          const FileDiff(path: 'a', status: GitChange.modified, hunks: [hunk]),
        ),
        isTrue,
      );
    });

    test('anything that creates, removes, moves or is not text cannot', () {
      for (final f in [
        const FileDiff(path: 'a', status: GitChange.added, hunks: [hunk]),
        const FileDiff(path: 'a', status: GitChange.deleted, hunks: [hunk]),
        const FileDiff(
          path: 'b',
          oldPath: 'a',
          status: GitChange.renamed,
          hunks: [hunk],
        ),
        const FileDiff(path: 'a', status: GitChange.modified, binary: true),
        const FileDiff(
          path: 'a',
          status: GitChange.modified,
          hunks: [hunk],
          lfs: LfsDiff(),
        ),
      ]) {
        expect(canApplyStashHunks(f), isFalse, reason: '${f.status}');
      }
    });
  });
}
