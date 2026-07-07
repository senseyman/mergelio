import 'package:flutter/material.dart';

import '../../domain/git/models.dart';
import 'rail_metrics.dart';

/// Paints one row of the commit graph rail: pass-through lane strands, the
/// commit node (ring + filled centre, larger for merges), a bezier dropping to
/// the second parent's lane for merges, and a bezier joining the parent lane
/// for branch starts.
class GraphRailPainter extends CustomPainter {
  final Commit c;
  final RailMetrics m;
  final List<Color> palette;
  final Color nodeFill;

  const GraphRailPainter({
    required this.c,
    required this.m,
    required this.palette,
    required this.nodeFill,
  });

  Color _laneColor(int lane) => palette[lane % palette.length];
  Color get _ciColor => palette[c.ci % palette.length];

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final y = m.nodeY;
    final x = m.laneX(c.lane);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Pass-through strands (lanes occupied both above and below this row).
    for (final l in c.through) {
      if (l == c.lane) continue;
      stroke.color = _laneColor(l);
      final lx = m.laneX(l);
      canvas.drawLine(Offset(lx, 0), Offset(lx, h), stroke);
    }

    // This commit's own strand: above the node unless it is a tip, below it
    // unless the strand ends here (root or branch start).
    stroke.color = _ciColor;
    if (!c.tip) canvas.drawLine(Offset(x, 0), Offset(x, y), stroke);
    if (c.parents.isNotEmpty && !c.branchStart) {
      canvas.drawLine(Offset(x, y), Offset(x, h), stroke);
    }

    // Merge: curve from the node down to the second parent's lane.
    final mf = c.mergeFrom;
    if (mf != null) {
      final tx = m.laneX(mf);
      stroke.color = _laneColor(mf);
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..cubicTo(tx, y + 6, tx, y, tx, h),
        stroke,
      );
    }

    // Branch start: this strand ends by curving into its parent's lane.
    final bi = c.branchInto;
    if (c.branchStart && bi != null) {
      final tx = m.laneX(bi);
      stroke.color = _ciColor;
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..cubicTo(x, y + 6, tx, y, tx, h),
        stroke,
      );
    }

    // Node: ring with a filled centre; merges draw slightly larger.
    final r = m.nodeRadius(merge: c.merge);
    canvas.drawCircle(Offset(x, y), r, Paint()..color = nodeFill);
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _ciColor,
    );
    canvas.drawCircle(
      Offset(x, y),
      m.centerRadius(merge: c.merge),
      Paint()..color = _ciColor,
    );
  }

  @override
  bool shouldRepaint(GraphRailPainter old) =>
      old.c != c ||
      old.m.compact != m.compact ||
      old.palette != palette ||
      old.nodeFill != nodeFill;
}
