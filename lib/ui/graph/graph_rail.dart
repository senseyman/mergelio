import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/bisect.dart';
import '../../domain/git/models.dart';
import 'rail_metrics.dart';

/// Colour for stash nodes and their pill — distinct from branch lane colours.
const stashNodeColor = Color(0xFF8B5CF6);

/// The colour a bisect verdict is drawn in, wherever it is drawn.
///
/// The rail node's tint and the commit row's text pill are two layers of one
/// design: a hue that reads at a glance, and the word that carries the same
/// verdict for anyone who cannot rely on hue. Two layers of one design have
/// to agree, so both resolve the verdict here rather than each keeping a copy
/// to drift apart the next time the theme moves. Resolved from tokens rather
/// than fixed like [stashNodeColor] because these three already have tokens,
/// tuned for contrast in each theme; a stash node has none.
Color bisectVerdictColor(BisectKind kind, AppTokens t) => switch (kind) {
  BisectKind.good => t.success,
  BisectKind.bad => t.danger,
  BisectKind.skip => t.textFaint,
};

/// Paints one row of the commit graph rail: pass-through lane strands, the
/// commit node (ring + filled centre, larger for merges), a bezier dropping to
/// the second parent's lane for merges, and a bezier joining the parent lane
/// for branch starts. A stash commit draws a distinct rounded-square node
/// instead of the usual ring.
class GraphRailPainter extends CustomPainter {
  final Commit c;
  final RailMetrics m;
  final List<Color> palette;
  final Color nodeFill;
  final bool stash;

  /// This commit's bisect verdict as a colour, or null when it has none.
  /// Tints the node's ring and centre in place of the lane colour — a
  /// glanceable layer only; the row's text pill is what carries the verdict
  /// for anyone who cannot read it from colour alone. Resolved by the caller
  /// through [bisectVerdictColor] so the pill beside it cannot disagree.
  final Color? bisectTint;

  const GraphRailPainter({
    required this.c,
    required this.m,
    required this.palette,
    required this.nodeFill,
    this.stash = false,
    this.bisectTint,
  });

  Color _laneColor(int lane) => palette[lane % palette.length];
  Color get _ciColor => palette[c.ci % palette.length];

  Color get _nodeColor => bisectTint ?? _ciColor;

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

    // Node: ring with a filled centre; merges draw slightly larger. A stash
    // draws a rounded-square node instead, so it reads as visually distinct
    // from ordinary commits at a glance.
    final r = m.nodeRadius(merge: c.merge);
    if (stash) {
      // A solid violet box (larger than the round commit nodes) with a
      // background-coloured inner square — reads clearly as a stash marker.
      final side = r * 2.4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: side, height: side),
          const Radius.circular(3),
        ),
        Paint()..color = stashNodeColor,
      );
      final inner = side * 0.42;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: inner, height: inner),
          const Radius.circular(1.5),
        ),
        Paint()..color = nodeFill,
      );
      return;
    }
    canvas.drawCircle(Offset(x, y), r, Paint()..color = nodeFill);
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _nodeColor,
    );
    canvas.drawCircle(
      Offset(x, y),
      m.centerRadius(merge: c.merge),
      Paint()..color = _nodeColor,
    );
  }

  @override
  bool shouldRepaint(GraphRailPainter old) =>
      old.c != c ||
      old.m.compact != m.compact ||
      old.palette != palette ||
      old.nodeFill != nodeFill ||
      old.stash != stash ||
      old.bisectTint != bisectTint;
}
