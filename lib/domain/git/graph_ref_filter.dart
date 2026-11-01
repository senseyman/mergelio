import 'dart:convert';

/// Which refs the commit graph starts its walk from, beyond the default of
/// every ref. Refs are full names (`refs/heads/x`, `refs/remotes/o/x`).
///
/// A hidden ref is left out as a starting point, so commits only it reaches
/// drop out of the graph. Soloed refs replace the default: only they and their
/// ancestry are shown. A ref is never both — choosing one clears the other.
class GraphRefFilter {
  final Set<String> hidden;
  final Set<String> solo;

  const GraphRefFilter({this.hidden = const {}, this.solo = const {}});

  static const none = GraphRefFilter();

  bool get isEmpty => hidden.isEmpty && solo.isEmpty;

  GraphRefFilter toggleHidden(String ref) => hidden.contains(ref)
      ? GraphRefFilter(hidden: {...hidden}..remove(ref), solo: solo)
      : GraphRefFilter(hidden: {...hidden, ref}, solo: {...solo}..remove(ref));

  GraphRefFilter toggleSolo(String ref) => solo.contains(ref)
      ? GraphRefFilter(hidden: hidden, solo: {...solo}..remove(ref))
      : GraphRefFilter(hidden: {...hidden}..remove(ref), solo: {...solo, ref});

  /// The part of this filter the graph is really applying, for saying what
  /// it shows. [live] is every full ref name that exists; [current] is the
  /// checked-out branch's short name, or null when HEAD is detached.
  ///
  /// Gone refs drop out. A hidden current branch is not in effect: the walk
  /// takes in HEAD whatever is excluded. While any soloed ref is live, hidden
  /// refs play no part; with none live, the walk falls back as [walkStart]
  /// does.
  GraphRefFilter effective({required Set<String> live, String? current}) {
    final liveSolo = solo.intersection(live);
    if (liveSolo.isNotEmpty) return GraphRefFilter(solo: liveSolo);
    return GraphRefFilter(
      hidden: {
        for (final r in hidden)
          if (live.contains(r) && r != 'refs/heads/$current') r,
      },
    );
  }

  /// The walk's starting points for `git log`. [liveSolo] is the part of
  /// [solo] that still exists: a soloed branch deleted since would make git
  /// fail the whole walk. With none left, the walk falls back to every ref
  /// bar the hidden ones rather than showing an empty graph.
  ///
  /// Stashes join only a walk from every ref: one on another branch would
  /// pull that branch's history into a soloed graph.
  ({List<String> args, bool stashes}) walkStart({
    required Set<String> liveSolo,
  }) {
    final soloed = [
      for (final r in solo)
        if (liveSolo.contains(r)) r,
    ]..sort();
    if (soloed.isNotEmpty) return (args: soloed, stashes: false);
    return (
      // `--exclude` narrows only the `--all` after it.
      args: [for (final r in hidden.toList()..sort()) '--exclude=$r', '--all'],
      stashes: true,
    );
  }

  String toJson() => jsonEncode({
    'hidden': hidden.toList()..sort(),
    'solo': solo.toList()..sort(),
  });

  /// A stored value that does not parse reads as no filter: losing a filter
  /// costs a click, a graph broken by bad state costs much more.
  static GraphRefFilter fromJson(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return none;
      Set<String> names(Object? v) => v is List
          ? {
              for (final e in v)
                if (e is String) e,
            }
          : {};
      if (m['hidden'] is! List? || m['solo'] is! List?) return none;
      return GraphRefFilter(hidden: names(m['hidden']), solo: names(m['solo']));
    } on FormatException {
      return none;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GraphRefFilter &&
      other.hidden.length == hidden.length &&
      other.solo.length == solo.length &&
      other.hidden.containsAll(hidden) &&
      other.solo.containsAll(solo);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(hidden),
    Object.hashAllUnordered(solo),
  );

  /// Stable text for a cache key: equal filters give equal keys.
  String get signature => toJson();
}

/// [ref] as people name it: `refs/heads/x` → `x`, `refs/remotes/o/x` →
/// `o/x`. Anything else is returned as given.
String shortRefName(String ref) {
  for (final prefix in const ['refs/heads/', 'refs/remotes/']) {
    if (ref.startsWith(prefix)) return ref.substring(prefix.length);
  }
  return ref;
}
