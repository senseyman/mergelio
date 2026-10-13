import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/models.dart';

/// Sentinel for selecting the WIP (uncommitted changes) row in the graph.
const wipSelection = 'WIP';

/// Sha of the selected graph row, [wipSelection] for the WIP node, or null
/// when nothing is selected. The details panel derives from this.
final selectedCommitProvider = StateProvider<String?>((_) => null);

/// Commits marked in the graph with Cmd/Ctrl- or Shift-click, for an action
/// that takes several at once, plus the anchor a Shift-click extends from.
/// Immutable: every gesture returns a new value.
///
/// Picks are not pruned when the history reloads — [oldestFirst] intersects
/// with the rows on screen at the moment of use, so a stale sha never acts.
class CommitPicks {
  final Set<String> shas;
  final String? anchor;

  const CommitPicks._({this.shas = const {}, this.anchor});

  static const none = CommitPicks._();

  bool get isEmpty => shas.isEmpty;
  int get length => shas.length;
  bool contains(String sha) => shas.contains(sha);

  /// Cmd/Ctrl-click: [sha] in or out. An empty set first takes in [seed], the
  /// commit selected by a plain click, so click-then-Cmd-click picks both.
  CommitPicks toggle(String sha, {String? seed}) {
    final next = {...shas};
    if (next.isEmpty && seed != null && seed != wipSelection && seed != sha) {
      next.add(seed);
    }
    if (!next.remove(sha)) next.add(sha);
    if (next.isEmpty) return none;
    return CommitPicks._(shas: next, anchor: sha);
  }

  /// Shift-click: the run of graph rows [order] from the anchor — or from
  /// [seed] when nothing is anchored — to [sha], replacing what was picked.
  /// With no usable start it is a pick of [sha] alone.
  CommitPicks extend(String sha, List<String> order, {String? seed}) {
    final start = anchor ?? seed;
    final from = start == null ? -1 : order.indexOf(start);
    final to = order.indexOf(sha);
    if (from < 0 || to < 0) return CommitPicks._(shas: {sha}, anchor: sha);
    final (lo, hi) = from <= to ? (from, to) : (to, from);
    return CommitPicks._(
      shas: order.sublist(lo, hi + 1).toSet(),
      anchor: start,
    );
  }

  /// The picks still in [order] (graph rows, newest first), oldest first —
  /// the order a replay has to apply them in, whatever order they were
  /// clicked in.
  List<String> oldestFirst(List<String> order) => [
    for (final sha in order.reversed)
      if (shas.contains(sha)) sha,
  ];
}

/// The graph's multi-commit picks, per repository.
final commitPicksProvider = StateProvider.family<CommitPicks, String>(
  (_, _) => CommitPicks.none,
);

/// The first merge commit in [commits], or null. A batch pick cannot hand each
/// merge its own mainline parent, so a merge has to be picked on its own.
Commit? firstMergeOf(Iterable<Commit> commits) {
  for (final c in commits) {
    if (c.merge) return c;
  }
  return null;
}
