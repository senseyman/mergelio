import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/ui/shell/branch_drop.dart';

void main() {
  const onBranch = BranchDropTarget.branch('main');
  const onCommit = BranchDropTarget.commit('abc123');

  group('branchDropOptions onto a branch', () {
    test('offers merge, rebase and a move for a non-current branch', () {
      expect(
        branchDropOptions(
          sourceIsRemote: false,
          sourceIsCurrent: false,
          target: onBranch,
          canFastForward: false,
        ),
        [BranchDrop.merge, BranchDrop.rebase, BranchDrop.moveHere],
      );
    });

    test('adds fast-forward only when the target is behind', () {
      expect(
        branchDropOptions(
          sourceIsRemote: false,
          sourceIsCurrent: false,
          target: onBranch,
          canFastForward: true,
        ),
        contains(BranchDrop.fastForward),
      );
    });

    test('offers the three reset modes when the source is current', () {
      final options = branchDropOptions(
        sourceIsRemote: false,
        sourceIsCurrent: true,
        target: onBranch,
        canFastForward: false,
      );
      expect(options, isNot(contains(BranchDrop.moveHere)));
      expect(
        options,
        containsAllInOrder([
          BranchDrop.resetSoft,
          BranchDrop.resetMixed,
          BranchDrop.resetHard,
        ]),
      );
    });

    test('limits a remote branch to merge and rebase', () {
      expect(
        branchDropOptions(
          sourceIsRemote: true,
          sourceIsCurrent: false,
          target: onBranch,
          canFastForward: true,
        ),
        [BranchDrop.merge, BranchDrop.rebase],
      );
    });
  });

  group('branchDropOptions onto a commit', () {
    test('offers rebase, move, cherry-pick and a new branch', () {
      expect(
        branchDropOptions(
          sourceIsRemote: false,
          sourceIsCurrent: false,
          target: onCommit,
          canFastForward: false,
        ),
        [
          BranchDrop.rebase,
          BranchDrop.moveHere,
          BranchDrop.cherryPick,
          BranchDrop.createBranch,
        ],
      );
    });

    test('never offers merge or fast-forward', () {
      final options = branchDropOptions(
        sourceIsRemote: false,
        sourceIsCurrent: true,
        target: onCommit,
        canFastForward: true,
      );
      expect(options, isNot(contains(BranchDrop.merge)));
      expect(options, isNot(contains(BranchDrop.fastForward)));
      expect(options, contains(BranchDrop.resetHard));
    });

    test('limits a remote branch to rebase', () {
      expect(
        branchDropOptions(
          sourceIsRemote: true,
          sourceIsCurrent: false,
          target: onCommit,
          canFastForward: false,
        ),
        [BranchDrop.rebase],
      );
    });
  });

  test('destructive options are the hard reset and the move', () {
    expect(
      BranchDrop.values.where((d) => d.destructive),
      unorderedEquals([BranchDrop.resetHard, BranchDrop.moveHere]),
    );
  });

  group('graphDropTarget', () {
    const branches = [
      Branch(name: 'main', current: true, tip: 'm1'),
      Branch(name: 'feat', tip: 'f1'),
    ];

    test('a row carrying a local branch is a drop on that branch', () {
      final t = graphDropTarget(
        source: 'feat',
        sha: 'm1',
        localRef: 'main',
        isStash: false,
        branches: branches,
      );
      expect(t?.isBranch, isTrue);
      expect(t?.ref, 'main');
    });

    test('any other row is a drop on the commit', () {
      final t = graphDropTarget(
        source: 'feat',
        sha: 'c9',
        localRef: null,
        isStash: false,
        branches: branches,
      );
      expect(t?.isBranch, isFalse);
      expect(t?.ref, 'c9');
    });

    test('rejects a branch dropped on itself or on its own tip', () {
      expect(
        graphDropTarget(
          source: 'main',
          sha: 'm1',
          localRef: 'main',
          isStash: false,
          branches: branches,
        ),
        isNull,
      );
      expect(
        graphDropTarget(
          source: 'feat',
          sha: 'f1',
          localRef: null,
          isStash: false,
          branches: branches,
        ),
        isNull,
      );
    });

    test('rejects a stash row, whose commit is not history', () {
      expect(
        graphDropTarget(
          source: 'feat',
          sha: 's1',
          localRef: null,
          isStash: true,
          branches: branches,
        ),
        isNull,
      );
    });
  });

  group('chipDropTarget', () {
    const branches = [
      Branch(name: 'main', current: true, tip: 'm1'),
      Branch(name: 'feat', tip: 'f1'),
      Branch(name: 'twin', tip: 'f1'),
    ];
    const remotes = [RemoteBranch(remote: 'origin', branch: 'main')];

    BranchDropTarget? on(String source, String chip) => chipDropTarget(
      source: source,
      chip: chip,
      branches: branches,
      remoteBranches: remotes,
    );

    test('a local chip is a drop on the branch it names', () {
      final t = on('feat', 'main');
      expect(t?.isBranch, isTrue);
      expect(t?.ref, 'main');
      expect(t?.remote, isNull);
    });

    test('a remote chip is a drop on that remote-tracking branch', () {
      final t = on('feat', 'origin/main');
      expect(t?.remote, remotes.single);
      expect(t?.ref, 'origin/main');
    });

    test('refuses the dragged branch itself, and a branch on its tip', () {
      expect(on('main', 'main'), isNull);
      expect(on('feat', 'twin'), isNull);
    });

    test('refuses the HEAD marker', () {
      expect(on('feat', 'HEAD'), isNull);
    });
  });

  test('a remote target only merges or rebases', () {
    expect(
      branchDropOptions(
        sourceIsRemote: false,
        sourceIsCurrent: true,
        target: BranchDropTarget.remote(
          RemoteBranch(remote: 'origin', branch: 'main'),
        ),
        canFastForward: true,
      ),
      [BranchDrop.merge, BranchDrop.rebase],
    );
  });
}
