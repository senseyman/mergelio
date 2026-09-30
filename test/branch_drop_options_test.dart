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

  group('resolveBranchDrop', () {
    const branches = [
      Branch(name: 'main', current: true, tip: 'm1'),
      Branch(name: 'feat', tip: 'f1'),
      Branch(name: 'twin', tip: 'f1'),
    ];
    const remotes = [RemoteBranch(remote: 'origin', branch: 'main', tip: 'o1')];

    BranchDropTarget? drop(String source, DropSpot spot) => resolveBranchDrop(
      source: source,
      spot: spot,
      branches: branches,
      remoteBranches: remotes,
    );

    test('a local label is a drop on the branch it names', () {
      final t = drop('feat', const DropSpot.label('main'));
      expect(t?.isBranch, isTrue);
      expect(t?.ref, 'main');
      expect(t?.remote, isNull);
    });

    test('a remote label is a drop on that remote-tracking branch', () {
      final t = drop('feat', const DropSpot.label('origin/main'));
      expect(t?.remote, remotes.single);
      expect(t?.ref, 'origin/main');
    });

    test(
      'anywhere else on a row is a drop on the commit, even a branch tip',
      () {
        final t = drop('feat', const DropSpot.commit('m1'));
        expect(t?.isBranch, isFalse);
        expect(t?.ref, 'm1');
      },
    );

    test('refuses a label that names no branch, such as HEAD', () {
      expect(drop('feat', const DropSpot.label('HEAD')), isNull);
    });

    test('refuses the dragged branch itself', () {
      expect(drop('main', const DropSpot.label('main')), isNull);
    });

    test("refuses the source's own tip, as a label or as a commit", () {
      expect(drop('feat', const DropSpot.label('twin')), isNull);
      expect(drop('feat', const DropSpot.commit('f1')), isNull);
      expect(drop('origin/main', const DropSpot.commit('o1')), isNull);
    });

    test('refuses a stash row, whose commit is not history', () {
      expect(drop('feat', const DropSpot.commit('s1', isStash: true)), isNull);
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
