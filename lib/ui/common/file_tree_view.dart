import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/file_tree.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/settings_controller.dart';

/// Icon toggle between a flat file list and a directory tree, bound to the
/// shared filesAsTree preference. Shared by every changed-file list.
class FileViewToggle extends ConsumerWidget {
  const FileViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final tree = ref.watch(settingsProvider.select((s) => s.filesAsTree));
    return Tooltip(
      message: tree ? l.ftvFlatList : l.ftvGroupByFolder,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => ref.read(settingsProvider.notifier).toggleFilesAsTree(),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            tree ? Icons.account_tree_outlined : Icons.format_list_bulleted,
            size: 15,
            color: t.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Renders a set of file [paths] either as a flat list or grouped into a
/// collapsible directory tree, delegating each file row to [fileRow] (which is
/// given the path and its indentation depth). Folder collapse state is local
/// and keyed by directory path, so it survives re-reads of the same file set.
class FileTreeView extends StatefulWidget {
  final List<String> paths;
  final bool tree;

  /// Builds a file row. [depth] is the tree nesting level (0 in flat mode) —
  /// use [fileIndent] for the left inset so files line up under their folder.
  final Widget Function(String path, int depth) fileRow;

  /// Placed on a folder row between its chevron and its icon — a control
  /// acting on every file under folder [dir].
  final Widget Function(String dir)? dirLeading;

  /// A right-click on folder row [dir], at global [position].
  final void Function(String dir, Offset position)? onDirSecondaryTap;

  const FileTreeView({
    super.key,
    required this.paths,
    required this.tree,
    required this.fileRow,
    this.dirLeading,
    this.onDirSecondaryTap,
  });

  /// Left inset for a row at [depth].
  static double indent(int depth) => 10 + depth * 14;

  @override
  State<FileTreeView> createState() => _FileTreeViewState();
}

class _FileTreeViewState extends State<FileTreeView> {
  final _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    if (!widget.tree) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final p in widget.paths) widget.fileRow(p, 0)],
      );
    }
    final rows = buildFileTree(widget.paths, _collapsed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          if (r is FileDirRow)
            _DirRow(
              row: r,
              leading: widget.dirLeading?.call(r.path),
              onSecondaryTap: widget.onDirSecondaryTap == null
                  ? null
                  : (position) => widget.onDirSecondaryTap!(r.path, position),
              onToggle: () => setState(() {
                if (!_collapsed.remove(r.path)) _collapsed.add(r.path);
              }),
            )
          else
            widget.fileRow((r as FileLeafRow).path, r.depth),
      ],
    );
  }
}

class _DirRow extends StatelessWidget {
  final FileDirRow row;
  final VoidCallback onToggle;
  final Widget? leading;
  final ValueChanged<Offset>? onSecondaryTap;
  const _DirRow({
    required this.row,
    required this.onToggle,
    this.leading,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onSecondaryTapUp: onSecondaryTap == null
          ? null
          : (d) => onSecondaryTap!(d.globalPosition),
      child: InkWell(
        onTap: onToggle,
        hoverColor: t.hover,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            FileTreeView.indent(row.depth),
            3,
            10,
            3,
          ),
          child: Row(
            children: [
              Icon(
                row.open ? Icons.expand_more : Icons.chevron_right,
                size: 15,
                color: t.textFaint,
              ),
              const SizedBox(width: 2),
              ?leading,
              Icon(
                row.open ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 13,
                color: t.textFaint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  row.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
