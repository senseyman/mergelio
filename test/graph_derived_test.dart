import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/ui/graph/graph_derived.dart';

Commit _c(
  String sha, {
  int lane = 0,
  int ci = 0,
  List<int> through = const [],
  List<GitRef> refs = const [],
  List<String> parents = const [],
}) => Commit(
  sha: sha,
  message: 'm',
  author: 'a',
  authorEmail: 'a@e',
  date: DateTime(2026),
  lane: lane,
  ci: ci,
  through: through,
  refs: refs,
  parents: parents,
);

const _head = GitRef(kind: RefKind.head, name: 'HEAD');

void main() {
  test('computes maxLane from lanes and pass-through lanes', () {
    final d = RepoData(
      commits: [
        _c('a', lane: 0),
        _c('b', lane: 1, through: [3]), // through lane 3 wins
        _c('c', lane: 2),
      ],
    );
    final g = computeGraphDerived(d);
    expect(g.maxLane, 3);
  });

  test('builds row index and lane lookup by sha', () {
    final d = RepoData(
      commits: [_c('a', lane: 0, ci: 5), _c('b', lane: 2, ci: 1)],
    );
    final g = computeGraphDerived(d);
    expect(g.rowIndex['a'], 0);
    expect(g.rowIndex['b'], 1);
    expect(g.laneOf['b'], (lane: 2, ci: 1));
  });

  test('empty repo yields zero maxLane and empty maps', () {
    final g = computeGraphDerived(const RepoData());
    expect(g.maxLane, 0);
    expect(g.rowIndex, isEmpty);
  });

  group('head', () {
    test('is the row and lane of the commit HEAD points at', () {
      // The issue's shape: a newer branch tip on top, HEAD lower on a side lane.
      final d = RepoData(
        commits: [
          _c('tip', lane: 0),
          _c('mid', lane: 0),
          _c('h', lane: 1, refs: const [_head]),
          _c('base', lane: 0),
        ],
      );

      expect(computeGraphDerived(d).head, (
        row: 2,
        lane: 1,
        merge: false,
        clear: true,
      ));
    });

    test('knows HEAD\'s lane is not clear when a node sits on it above', () {
      final d = RepoData(
        commits: [
          _c('other', lane: 1),
          _c('h', lane: 1, refs: const [_head]),
        ],
      );

      expect(computeGraphDerived(d).head?.clear, isFalse);
    });

    test('knows HEAD\'s lane is not clear when a strand runs down it', () {
      final d = RepoData(
        commits: [
          _c('top', lane: 0, through: [1]),
          _c('h', lane: 1, refs: const [_head]),
        ],
      );

      expect(computeGraphDerived(d).head?.clear, isFalse);
    });

    test('a clear row alongside HEAD\'s lane keeps it clear', () {
      final d = RepoData(
        commits: [
          _c('top', lane: 0, through: [0, 2]),
          _c('h', lane: 1, refs: const [_head]),
        ],
      );

      expect(computeGraphDerived(d).head?.clear, isTrue);
    });

    test('knows when HEAD is a merge, whose node is drawn larger', () {
      final d = RepoData(
        commits: [
          _c('h', refs: const [_head], parents: const ['a', 'b']),
        ],
      );

      expect(computeGraphDerived(d).head?.merge, isTrue);
    });

    test('is null when HEAD is not among the loaded commits', () {
      final d = RepoData(commits: [_c('a'), _c('b')]);

      expect(computeGraphDerived(d).head, isNull);
    });
  });
}
