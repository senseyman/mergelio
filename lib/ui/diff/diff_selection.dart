import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/gen/app_localizations.dart';
import '../common/dialogs.dart';

/// Right-click menu for the diff body.
///
/// Flutter's own selection toolbar refuses to open while nothing is selected,
/// and it only offers Select all once the region reports content. Between the
/// two, a right-click on a hunk header, the gutter or blank space did nothing
/// at all until the user had left-clicked somewhere selectable first. This
/// menu is always available, and matches the menus used elsewhere in the app.
/// [stageLabel], [onStageLines] and [onDiscardLines] are supplied when a run of
/// lines is picked out and the diff can be staged; they act on that run only.
/// [onLineHistory] is supplied whenever a run is picked out, staged or not —
/// asking what happened to those lines does not change anything.
Future<void> showDiffSelectionMenu(
  BuildContext context,
  Offset at, {
  String? stageLabel,
  VoidCallback? onStageLines,
  VoidCallback? onDiscardLines,
  VoidCallback? onLineHistory,
}) async {
  final l = AppLocalizations.of(context);
  final region = context.findAncestorStateOfType<SelectableRegionState>();
  if (region == null) return;

  await showContextMenu<void>(
    context: context,
    position: at,
    items: [
      if (onStageLines != null)
        PopupMenuItem(
          height: 34,
          onTap: onStageLines,
          child: Text(
            stageLabel ?? l.diffStageSelectedLines,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      if (onDiscardLines != null)
        PopupMenuItem(
          height: 34,
          onTap: onDiscardLines,
          child: Text(
            l.diffDiscardSelectedLines,
            style: TextStyle(fontSize: 13),
          ),
        ),
      if (onLineHistory != null)
        PopupMenuItem(
          height: 34,
          onTap: onLineHistory,
          child: Text(l.lhLineHistory, style: const TextStyle(fontSize: 13)),
        ),
      if (onStageLines != null ||
          onDiscardLines != null ||
          onLineHistory != null)
        const PopupMenuDivider(height: 1),
      PopupMenuItem(
        height: 34,
        onTap: () {
          // Focus first, so the copy shortcut reaches the region afterwards.
          region.widget.focusNode?.requestFocus();
          region.selectAll();
        },
        child: Text(l.diffSelectAll, style: TextStyle(fontSize: 13)),
      ),
    ],
  );
}

/// Gives one diff row's text its own line break when copied.
///
/// Flutter concatenates the selected content of separate selectables with no
/// separator, so a selection spanning rows arrives as one run-on line. Joining
/// at a container above the list does not help: [Scrollable] installs its own
/// aggregating delegate underneath, and that is where the rows are flattened.
/// So each row carries its own break instead.
class _LineBreakDelegate extends StaticSelectionContainerDelegate {
  _LineBreakDelegate(this.rowText);

  /// The row's full text, used to tell a selection that runs off the end of
  /// this row from one that stops inside it.
  String rowText;

  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content == null) return null;
    final selected = content.plainText;
    // A selection reaching the end of the row either continues onto the next
    // row or takes the whole line, and in both cases carries the line break.
    // One that stops mid-row is where the drag ended, so it takes no break.
    if (selected.isEmpty || !rowText.endsWith(selected)) return content;
    return SelectedContent(plainText: '$selected\n');
  }
}

/// Wraps the text of a single diff row so copying a multi-row selection keeps
/// the rows on separate lines.
class DiffSelectableLine extends StatefulWidget {
  /// The row's full text, as it would be copied.
  final String text;
  final Widget child;

  const DiffSelectableLine({
    super.key,
    required this.text,
    required this.child,
  });

  @override
  State<DiffSelectableLine> createState() => _DiffSelectableLineState();
}

class _DiffSelectableLineState extends State<DiffSelectableLine> {
  late final _delegate = _LineBreakDelegate(widget.text);

  @override
  void didUpdateWidget(DiffSelectableLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    // List rows are recycled onto different lines as the diff scrolls.
    _delegate.rowText = widget.text;
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}
