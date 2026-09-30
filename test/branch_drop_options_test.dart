import 'package:flutter_test/flutter_test.dart';
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
}
