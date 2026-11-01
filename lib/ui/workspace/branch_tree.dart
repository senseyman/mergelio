import '../../domain/git/models.dart';

/// A single flattened row of the branch folder tree: either a [BranchFolderRow]
/// (a `/`-delimited grouping) or a [BranchLeafRow] (an actual branch). [depth]
/// is the nesting level for indentation.
sealed class BranchTreeRow {
  final int depth;
  const BranchTreeRow(this.depth);
}

class BranchFolderRow extends BranchTreeRow {
  final String name;

  /// Stable id used to persist this folder's collapse state.
  final String id;
  final bool open;
  const BranchFolderRow({
    required this.name,
    required this.id,
    required this.open,
    required int depth,
  }) : super(depth);
}

class BranchLeafRow extends BranchTreeRow {
  final Branch branch;
  const BranchLeafRow({required this.branch, required int depth})
    : super(depth);
}

/// Groups [branches] into a `/`-delimited folder tree and flattens it depth
/// first to ordered rows. At each level folders come before branches, both
/// sorted by name. A folder whose id is truthy in [collapsed] is emitted but
/// its descendants are omitted.
///
/// [forceOpen] shows every folder open whatever [collapsed] says, for a
/// filtered list where a match must not hide inside a closed folder; the
/// saved state itself is left alone.
List<BranchTreeRow> buildBranchTree(
  List<Branch> branches,
  Map<String, bool> collapsed, {
  bool forceOpen = false,
}) {
  final root = _Node();
  for (final b in branches) {
    var node = root;
    final parts = b.name.split('/');
    for (var i = 0; i < parts.length; i++) {
      if (i == parts.length - 1) {
        node.branches.add(b);
      } else {
        node = node.dirs.putIfAbsent(parts[i], () => _Node());
      }
    }
  }
  final rows = <BranchTreeRow>[];
  _emit(root, '', 0, rows, forceOpen ? const {} : collapsed);
  return rows;
}

void _emit(
  _Node node,
  String prefix,
  int depth,
  List<BranchTreeRow> rows,
  Map<String, bool> collapsed,
) {
  for (final name in node.dirs.keys.toList()..sort()) {
    final id = 'branchdir:$prefix$name';
    final open = !(collapsed[id] ?? false);
    rows.add(BranchFolderRow(name: name, id: id, open: open, depth: depth));
    if (open) {
      _emit(node.dirs[name]!, '$prefix$name/', depth + 1, rows, collapsed);
    }
  }
  node.branches.sort((a, b) => a.name.compareTo(b.name));
  for (final b in node.branches) {
    rows.add(BranchLeafRow(branch: b, depth: depth));
  }
}

class _Node {
  final Map<String, _Node> dirs = {};
  final List<Branch> branches = [];
}

/// The [branches] whose full name holds every whitespace-separated word of
/// [query], ignoring case. A blank query keeps them all.
List<Branch> filterBranches(List<Branch> branches, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return branches;
  return [
    for (final b in branches)
      if (words.every(b.name.toLowerCase().contains)) b,
  ];
}
