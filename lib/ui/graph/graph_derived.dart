import '../../state/repo_data.dart';
import '../../domain/git/models.dart';
import 'commit_columns.dart';
import 'wip_link.dart';

/// The O(n) graph derivations that depend only on the commit list, not on
/// transient UI state (selection, hover, search, settings). Computing these
/// once per [RepoData] and caching keeps them off the per-rebuild path — the
/// difference between smooth and janky scrolling on large (50k+) repositories.
class GraphDerived {
  final int maxLane;
  final Map<String, List<String>> labels;
  final Map<String, int> rowIndex;
  final Map<String, ({int lane, int ci})> laneOf;

  /// Where HEAD's commit is drawn — the commit the uncommitted-changes row
  /// hangs from — or null when it is not among the loaded commits.
  final WipHead? head;

  const GraphDerived({
    required this.maxLane,
    required this.labels,
    required this.rowIndex,
    required this.laneOf,
    this.head,
  });
}

GraphDerived computeGraphDerived(RepoData d) {
  var maxLane = 0;
  final rowIndex = <String, int>{};
  final laneOf = <String, ({int lane, int ci})>{};
  WipHead? head;
  for (var j = 0; j < d.commits.length; j++) {
    final c = d.commits[j];
    if (c.lane > maxLane) maxLane = c.lane;
    for (final l in c.through) {
      if (l > maxLane) maxLane = l;
    }
    rowIndex[c.sha] = j;
    laneOf[c.sha] = (lane: c.lane, ci: c.ci);
    if (head == null && c.refs.any((r) => r.kind == RefKind.head)) {
      head = (row: j, lane: c.lane, merge: c.merge, clear: true);
    }
  }
  // A lane is reused once its branch ends, so HEAD being a tip does not mean
  // its lane is empty above it: look at every row up to it.
  final h = head;
  if (h != null) {
    for (var j = 0; j < h.row; j++) {
      final c = d.commits[j];
      if (c.lane == h.lane || c.through.contains(h.lane)) {
        head = (row: h.row, lane: h.lane, merge: h.merge, clear: false);
        break;
      }
    }
  }
  return GraphDerived(
    maxLane: maxLane,
    labels: deriveBranchLabels(d.commits),
    rowIndex: rowIndex,
    laneOf: laneOf,
    head: head,
  );
}
