/// A flattened row of a file tree: either a [FileDirRow] (a `/`-delimited
/// directory grouping) or a [FileLeafRow] (an actual file). [depth] is the
/// nesting level for indentation.
sealed class FileTreeRow {
  final int depth;
  const FileTreeRow(this.depth);
}

class FileDirRow extends FileTreeRow {
  /// Display label (one or more joined segments when compacted).
  final String name;

  /// Full directory path — the key used to persist/track collapse state.
  final String path;
  final bool open;
  const FileDirRow({
    required this.name,
    required this.path,
    required this.open,
    required int depth,
  }) : super(depth);
}

class FileLeafRow extends FileTreeRow {
  final String path;
  final String name; // basename
  const FileLeafRow({
    required this.path,
    required this.name,
    required int depth,
  }) : super(depth);
}

/// Groups [paths] into a directory tree and flattens it depth-first to ordered
/// rows: at each level directories come first (sorted), then files (sorted by
/// name). A directory whose full path is in [collapsed] is emitted but its
/// descendants are omitted.
///
/// Single-child directory chains are compacted into one row (e.g. `lib/ui/
/// graph`) so deep paths stay readable — matching how editors show them.
List<FileTreeRow> buildFileTree(List<String> paths, Set<String> collapsed) {
  final root = _Node();
  for (final p in paths) {
    var node = root;
    final parts = p.split('/');
    for (var i = 0; i < parts.length; i++) {
      if (i == parts.length - 1) {
        node.files.add(p);
      } else {
        node = node.dirs.putIfAbsent(parts[i], () => _Node());
      }
    }
  }
  final rows = <FileTreeRow>[];
  _emit(root, '', '', 0, rows, collapsed);
  return rows;
}

void _emit(
  _Node node,
  String pathPrefix,
  String labelPrefix,
  int depth,
  List<FileTreeRow> rows,
  Set<String> collapsed,
) {
  for (final name in node.dirs.keys.toList()..sort()) {
    var child = node.dirs[name]!;
    var path = '$pathPrefix$name';
    var label = '$labelPrefix$name';
    // Compact a run of single-child directories with no files into one row.
    while (child.dirs.length == 1 && child.files.isEmpty) {
      final only = child.dirs.keys.first;
      path = '$path/$only';
      label = '$label/$only';
      child = child.dirs[only]!;
    }
    final open = !collapsed.contains(path);
    rows.add(FileDirRow(name: label, path: path, open: open, depth: depth));
    if (open) _emit(child, '$path/', '', depth + 1, rows, collapsed);
  }
  node.files.sort((a, b) => _base(a).compareTo(_base(b)));
  for (final f in node.files) {
    rows.add(FileLeafRow(path: f, name: _base(f), depth: depth));
  }
}

String _base(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

class _Node {
  final Map<String, _Node> dirs = {};
  final List<String> files = [];
}
