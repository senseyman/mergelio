import '../../domain/git/models.dart';

/// The toggleable graph meta columns, id → display label. Shared by the graph
/// header "Columns" menu and Preferences so both stay in sync.
const graphColumnLabels = {
  'branch': 'Branch',
  'author': 'Author',
  'date': 'Date',
  'sha': 'SHA',
};

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats [d] per [format]: 'medium' (Jul 2, 2026), 'iso' (2026-07-02) or
/// 'short' (07/02/26).
String formatCommitDate(DateTime d, {String format = 'medium'}) {
  String p2(int n) => n.toString().padLeft(2, '0');
  return switch (format) {
    'iso' => '${d.year}-${p2(d.month)}-${p2(d.day)}',
    'short' => '${p2(d.month)}/${p2(d.day)}/${p2(d.year % 100)}',
    _ => '${_months[d.month - 1]} ${d.day}, ${d.year}',
  };
}

/// Branch refs that name a commit: all of its local branches, or — when it has
/// no local branch — its remote-tracking branches (kept with their `remote/`
/// prefix so the gutter tells a remote-only branch apart). A local ref
/// represents any remote at the same commit, so remotes are suppressed there to
/// avoid showing `main` and `origin/main` twice. Tags are excluded.
List<String> _ownRefs(Commit c) {
  final locals = <String>[];
  final remotes = <String>[];
  for (final r in c.refs) {
    if (r.kind == RefKind.local) {
      locals.add(r.name);
    } else if (r.kind == RefKind.remote) {
      remotes.add(r.name);
    }
  }
  return locals.isNotEmpty ? locals : remotes;
}

/// Branch column labels per commit sha. A commit is named by *all* of its own
/// branch refs (so several branches sitting on one commit are each shown), else
/// it inherits the single branch of its nearest first-parent descendant — so
/// shared history stays on the base branch instead of being claimed by a newer
/// branch that also contains it.
///
/// [commits] must be newest-first topological order (a child before its
/// parents), as produced by `git log --topo-order`.
Map<String, List<String>> deriveBranchLabels(List<Commit> commits) {
  final display = <String, List<String>>{};
  // The single primary label that flows down a first-parent segment.
  final segment = <String, String>{};
  for (final c in commits) {
    final own = _ownRefs(c);
    final List<String> labels;
    if (own.isNotEmpty) {
      // Own refs always win over a label a descendant propagated down.
      labels = own;
    } else {
      final inherited = segment[c.sha];
      if (inherited == null) continue;
      labels = [inherited];
    }
    display[c.sha] = labels;
    if (c.parents.isNotEmpty) {
      // Only the primary (first) ref propagates; the nearest descendant claims
      // the first parent and a later (older) path does not overwrite it.
      segment.putIfAbsent(c.parents.first, () => labels.first);
    }
  }
  return display;
}
