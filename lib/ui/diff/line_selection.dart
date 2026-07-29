import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A run of diff lines picked out for staging or discarding, held as the two
/// ends of a drag rather than a set: the anchor is where the gesture started
/// and stays put, the focus follows the pointer.
///
/// A selection never leaves the hunk it started in — a patch is built per hunk,
/// so a run spanning two of them could not be applied as one operation.
class DiffLineSelection {
  /// Path of the file the lines belong to, so a selection made in one file
  /// cannot be mistaken for the same indices in another.
  final String path;
  final int hunkIndex;

  /// Indices into the hunk's line list.
  final int anchor;
  final int focus;

  const DiffLineSelection({
    required this.path,
    required this.hunkIndex,
    required this.anchor,
    required this.focus,
  });

  int get start => math.min(anchor, focus);
  int get end => math.max(anchor, focus);

  Set<int> get lines => {for (var i = start; i <= end; i++) i};

  bool covers(String path, int hunkIndex, int line) =>
      path == this.path &&
      hunkIndex == this.hunkIndex &&
      line >= start &&
      line <= end;

  /// The same selection dragged out to [line]; the anchor does not move, so
  /// pulling back past it reverses the run rather than starting a new one.
  DiffLineSelection extendTo(int line) => DiffLineSelection(
    path: path,
    hunkIndex: hunkIndex,
    anchor: anchor,
    focus: line,
  );

  @override
  bool operator ==(Object other) =>
      other is DiffLineSelection &&
      other.path == path &&
      other.hunkIndex == hunkIndex &&
      other.anchor == anchor &&
      other.focus == focus;

  @override
  int get hashCode => Object.hash(path, hunkIndex, anchor, focus);
}

/// Lines currently picked out in the open diff, or null when none are.
/// Cleared whenever the sheet moves to another file or side.
final lineSelectionProvider = StateProvider<DiffLineSelection?>((_) => null);

/// True while the pointer is down and dragging out a run of lines, so a row
/// the pointer travels over knows to extend the selection rather than ignore
/// the hover.
final lineDraggingProvider = StateProvider<bool>((_) => false);

/// Wraps a diff row's gutter so pressing it picks that line out, dragging runs
/// the selection to wherever the pointer goes, and shift-clicking extends from
/// the existing anchor.
///
/// It goes on the gutter rather than the whole row because the code itself is
/// text-selectable; the two gestures would otherwise fight over the drag.
class LineSelectHandle extends ConsumerWidget {
  final String path;
  final int hunkIndex;

  /// Index of the line in the hunk, or null for the blank half of a split row,
  /// which has no line to pick.
  final int? lineIndex;
  final Widget child;

  const LineSelectHandle({
    super.key,
    required this.path,
    required this.hunkIndex,
    required this.lineIndex,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = lineIndex;
    if (index == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!ref.read(lineDraggingProvider)) return;
        final current = ref.read(lineSelectionProvider);
        // A drag stays in the hunk it started in: one patch, one operation.
        if (current == null ||
            current.path != path ||
            current.hunkIndex != hunkIndex) {
          return;
        }
        ref.read(lineSelectionProvider.notifier).state = current.extendTo(
          index,
        );
      },
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryButton) return;
          final current = ref.read(lineSelectionProvider);
          final shift = HardwareKeyboard.instance.isShiftPressed;
          final extending =
              shift &&
              current != null &&
              current.path == path &&
              current.hunkIndex == hunkIndex;
          ref.read(lineSelectionProvider.notifier).state = extending
              ? current.extendTo(index)
              : DiffLineSelection(
                  path: path,
                  hunkIndex: hunkIndex,
                  anchor: index,
                  focus: index,
                );
          ref.read(lineDraggingProvider.notifier).state = true;
        },
        child: child,
      ),
    );
  }
}
