import '../state/project_files.dart';

/// One rendered row of the project navigator. [path] is repo-relative and
/// `/`-separated; [depth] is the nesting level for indentation.
sealed class ProjectRow {
  final int depth;
  final String path;
  const ProjectRow({required this.depth, required this.path});
}

class ProjectDirRow extends ProjectRow {
  final String name;
  final bool open;
  const ProjectDirRow({
    required this.name,
    required this.open,
    required super.depth,
    required super.path,
  });
}

class ProjectFileRow extends ProjectRow {
  final String name;
  final bool isLink;
  const ProjectFileRow({
    required this.name,
    required super.depth,
    required super.path,
    this.isLink = false,
  });
}

/// An expanded directory whose listing has not arrived yet.
class ProjectLoadingRow extends ProjectRow {
  const ProjectLoadingRow({required super.depth, required super.path});
}

/// Stands in for the entries a directory listing dropped at the cap.
class ProjectMoreRow extends ProjectRow {
  final int count;
  const ProjectMoreRow({
    required this.count,
    required super.depth,
    required super.path,
  });
}

/// A directory that could not be read. Shown in place of its children so one
/// unreadable folder does not break the rest of the tree.
class ProjectErrorRow extends ProjectRow {
  final String message;
  const ProjectErrorRow({
    required this.message,
    required super.depth,
    required super.path,
  });
}

/// Flattens the part of the project that has been loaded so far into ordered
/// rows. Descends only into directories that are both expanded and already
/// listed; an expanded directory still awaiting its listing yields a loading
/// row.
///
/// Unlike the changed-file tree, single-child directory chains are not
/// compacted: the children of an unopened directory are unknown, so every
/// level has to stay separately expandable.
List<ProjectRow> flattenProject({
  required Map<String, DirListing> loaded,
  required Set<String> expanded,
  bool hideIgnored = false,
  Set<String> ignored = const {},
}) {
  final rows = <ProjectRow>[];
  _emit('', 0, loaded, expanded, hideIgnored, ignored, rows);
  return rows;
}

void _emit(
  String relDir,
  int depth,
  Map<String, DirListing> loaded,
  Set<String> expanded,
  bool hideIgnored,
  Set<String> ignored,
  List<ProjectRow> rows,
) {
  final listing = loaded[relDir];
  if (listing == null) {
    rows.add(ProjectLoadingRow(depth: depth, path: relDir));
    return;
  }
  if (listing.error != null) {
    rows.add(
      ProjectErrorRow(message: listing.error!, depth: depth, path: relDir),
    );
    return;
  }
  for (final e in listing.entries) {
    final path = relDir.isEmpty ? e.name : '$relDir/${e.name}';
    if (hideIgnored && ignored.contains(path)) continue;
    if (e.isDir) {
      final open = expanded.contains(path);
      rows.add(
        ProjectDirRow(name: e.name, open: open, depth: depth, path: path),
      );
      if (open) {
        _emit(path, depth + 1, loaded, expanded, hideIgnored, ignored, rows);
      }
    } else {
      rows.add(
        ProjectFileRow(
          name: e.name,
          depth: depth,
          path: path,
          isLink: e.isLink,
        ),
      );
    }
  }
  if (listing.truncated > 0) {
    rows.add(
      ProjectMoreRow(count: listing.truncated, depth: depth, path: relDir),
    );
  }
}
