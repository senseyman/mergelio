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

String? _ownRef(Commit c) {
  for (final r in c.refs) {
    if (r.kind == RefKind.local) return r.name;
  }
  return null;
}

/// Branch column label per commit sha. A commit is named by its own local ref
/// if it has one, else it inherits the branch of its nearest first-parent
/// descendant — so shared history stays on the base branch instead of being
/// claimed by whichever newer branch also happens to contain it.
///
/// [commits] must be newest-first topological order (a child before its
/// parents), as produced by `git log --topo-order`.
Map<String, String> deriveBranchLabels(List<Commit> commits) {
  final labels = <String, String>{};
  for (final c in commits) {
    // Own ref always wins over a label a descendant may have propagated down.
    final label = _ownRef(c) ?? labels[c.sha];
    if (label == null) continue;
    labels[c.sha] = label;
    if (c.parents.isNotEmpty) {
      // Nearest descendant claims the first parent; a later (older) path that
      // reaches the same commit does not overwrite it.
      labels.putIfAbsent(c.parents.first, () => label);
    }
  }
  return labels;
}
