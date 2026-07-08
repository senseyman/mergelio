import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/ui/graph/graph_derived.dart';

Commit _c(
  String sha, {
  int lane = 0,
  int ci = 0,
  List<int> through = const [],
}) => Commit(
  sha: sha,
  message: 'm',
  author: 'a',
  authorEmail: 'a@e',
  date: DateTime(2026),
  lane: lane,
  ci: ci,
  through: through,
);

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
    expect(g.segments, isEmpty);
  });
}
