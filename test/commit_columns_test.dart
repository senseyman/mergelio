import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/ui/graph/commit_columns.dart';

Commit _c(
  String sha, {
  List<String> parents = const [],
  List<GitRef> refs = const [],
}) => Commit(
  sha: sha,
  message: '',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026),
  parents: parents,
  refs: refs,
);

GitRef _local(String name) => GitRef(kind: RefKind.local, name: name);
GitRef _remote(String name) => GitRef(kind: RefKind.remote, name: name);
GitRef _head() => const GitRef(kind: RefKind.head, name: 'HEAD');

void main() {
  test('formats dates as "Mon D, YYYY"', () {
    expect(formatCommitDate(DateTime(2026, 7, 2)), 'Jul 2, 2026');
    expect(formatCommitDate(DateTime(2025, 12, 31)), 'Dec 31, 2025');
    expect(formatCommitDate(DateTime(2024, 1, 9)), 'Jan 9, 2024');
  });

  group('deriveBranchLabels', () {
    test('a commit is labelled by its own local ref', () {
      final labels = deriveBranchLabels([
        _c('tip', parents: const [], refs: [_local('main')]),
      ]);
      expect(labels['tip'], ['main']);
    });

    test(
      'a remote-only commit is labelled by its remote ref, prefix and all',
      () {
        final labels = deriveBranchLabels([
          _c('x', refs: [_remote('origin/feature')]),
        ]);
        expect(labels['x'], ['origin/feature']);
      },
    );

    test('a local ref suppresses a remote on the same commit', () {
      final labels = deriveBranchLabels([
        _c('x', refs: [_remote('origin/main'), _local('main')]),
      ]);
      expect(labels['x'], ['main']);
    });

    test('multiple local branches on one commit are all shown', () {
      final labels = deriveBranchLabels([
        _c('x', refs: [_local('main'), _local('feature/submodules')]),
      ]);
      expect(labels['x'], ['main', 'feature/submodules']);
    });

    test('a tag ref does not name a commit', () {
      final labels = deriveBranchLabels([
        _c(
          'x',
          refs: const [GitRef(kind: RefKind.tag, name: 'v1')],
        ),
      ]);
      expect(labels['x'], isNull);
    });

    test('a remote ref propagates down first parents like a local one', () {
      // origin/feature → base(root). Newest first, base has no ref of its own.
      final labels = deriveBranchLabels([
        _c('feat', parents: const ['base'], refs: [_remote('origin/feature')]),
        _c('base'),
      ]);
      expect(labels['feat'], ['origin/feature']);
      expect(labels['base'], ['origin/feature']);
    });

    test('shared ancestors take the nearest descendant branch, not a '
        'newer branch that also contains them', () {
      // feat/stage-3 → main → old1 → old2 (root). Newest first.
      final labels = deriveBranchLabels([
        _c('s3', parents: const ['main'], refs: [_local('feat/stage-3')]),
        _c('main', parents: const ['old1'], refs: [_local('main')]),
        _c('old1', parents: const ['old2']),
        _c('old2'),
      ]);
      expect(labels['s3'], ['feat/stage-3']);
      // main and everything below it belongs to main — not feat/stage-3, even
      // though stage-3 also contains these commits.
      expect(labels['main'], ['main']);
      expect(labels['old1'], ['main']);
      expect(labels['old2'], ['main']);
    });

    test('only the primary ref of a multi-ref tip propagates down', () {
      // main + feature both tip 'x'; base inherits only the first (main).
      final labels = deriveBranchLabels([
        _c(
          'x',
          parents: const ['base'],
          refs: [_local('main'), _local('feat')],
        ),
        _c('base'),
      ]);
      expect(labels['x'], ['main', 'feat']);
      expect(labels['base'], ['main']);
    });

    test('a commit\'s own ref wins over an inheriting descendant', () {
      final labels = deriveBranchLabels([
        _c('feat', parents: const ['base'], refs: [_local('feature')]),
        _c('base', refs: [_local('main')]),
      ]);
      expect(labels['base'], ['main']);
    });

    test('a merged branch keeps its own line via first parent', () {
      // merge → [m1, f2];  f2 → f1 → m1(root, main).
      final labels = deriveBranchLabels([
        _c('merge', parents: const ['m1', 'f2'], refs: [_local('main')]),
        _c('f2', parents: const ['f1'], refs: [_local('feature')]),
        _c('f1', parents: const ['m1']),
        _c('m1', refs: [_local('main')]),
      ]);
      expect(labels['f2'], ['feature']);
      expect(labels['f1'], ['feature']); // first-parent descendant is f2
      expect(labels['m1'], ['main']);
    });
  });

  group('branchColumnChips', () {
    test('a HEAD ref adds a HEAD chip above the branch chips', () {
      final chips = branchColumnChips(
        _c('x', refs: [_head(), _local('main')]),
        ['main'],
        showBranchLabel: true,
      );
      expect(chips, const [
        BranchChip(name: 'HEAD', isHead: true),
        BranchChip(name: 'main', isHead: false),
      ]);
    });

    test('a detached HEAD shows a HEAD chip even with no branch label', () {
      final chips = branchColumnChips(
        _c('x', refs: [_head()]),
        const [],
        showBranchLabel: false,
      );
      expect(chips, const [BranchChip(name: 'HEAD', isHead: true)]);
    });

    test('without a HEAD ref only the branch chips show', () {
      final chips = branchColumnChips(_c('x', refs: [_local('main')]), [
        'main',
      ], showBranchLabel: true);
      expect(chips, const [BranchChip(name: 'main', isHead: false)]);
    });

    test('branch labels are suppressed off the segment top', () {
      final chips = branchColumnChips(_c('x', refs: [_local('main')]), [
        'main',
      ], showBranchLabel: false);
      expect(chips, isEmpty);
    });
  });
}
