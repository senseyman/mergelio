import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// A 7px draggable divider between panels. Reports pixel deltas via [onDrag];
/// the parent applies and persists the resulting width.
class ResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  const ResizeHandle({super.key, required this.onDrag});

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lit = _hover || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(width: 1, color: lit ? t.accent : t.border),
          ),
        ),
      ),
    );
  }
}
