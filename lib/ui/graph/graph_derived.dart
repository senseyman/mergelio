import '../../domain/git/models.dart';
import '../../state/repo_data.dart';
import 'commit_columns.dart';
import 'squash_overlay.dart';

/// The O(n) graph derivations that depend only on the commit list, not on
/// transient UI state (selection, hover, search, settings). Computing these
/// once per [RepoData] and caching keeps them off the per-rebuild path — the
/// difference between smooth and janky scrolling on large (50k+) repositories.
class GraphDerived {
  final int maxLane;
  final Map<String, List<String>> labels;
  final Map<String, int> rowIndex;
  final Map<String, ({int lane, int ci})> laneOf;
  final List<SquashSegment> segments;
  // Sha → the name of a local branch ref sitting on that commit (drop target
  // for branch-onto-commit DnD). Precomputed so the row builder does an O(1)
  // lookup instead of scanning refs per row per frame.
  final Map<String, String> localRefBySha;

  const GraphDerived({
    required this.maxLane,
    required this.labels,
    required this.rowIndex,
    required this.laneOf,
    required this.segments,
    required this.localRefBySha,
  });
}

GraphDerived computeGraphDerived(RepoData d) {
  var maxLane = 0;
  final rowIndex = <String, int>{};
  final laneOf = <String, ({int lane, int ci})>{};
  final localRefBySha = <String, String>{};
  for (var j = 0; j < d.commits.length; j++) {
    final c = d.commits[j];
    if (c.lane > maxLane) maxLane = c.lane;
    for (final l in c.through) {
      if (l > maxLane) maxLane = l;
    }
    rowIndex[c.sha] = j;
    laneOf[c.sha] = (lane: c.lane, ci: c.ci);
    for (final r in c.refs) {
      if (r.kind == RefKind.local) {
        localRefBySha[c.sha] = r.name;
        break;
      }
    }
  }
  return GraphDerived(
    maxLane: maxLane,
    labels: deriveBranchLabels(d.commits),
    rowIndex: rowIndex,
    laneOf: laneOf,
    segments: resolveSquashSegments(d.squashLinks, rowIndex, laneOf: laneOf),
    localRefBySha: localRefBySha,
  );
}
