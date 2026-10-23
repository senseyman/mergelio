import 'package:flutter/material.dart';

import 'rail_metrics.dart';

/// HEAD's commit as the graph draws it: its row among the commits (the
/// uncommitted-changes row above them not counted), its lane, whether it is a
/// merge, whose node is drawn larger, and whether its lane is clear above it —
/// no node and no strand on it in any row between the uncommitted-changes row
/// and HEAD.
typedef WipHead = ({int row, int lane, bool merge, bool clear});

/// The connector from the uncommitted-changes ring to HEAD's node, in the
/// graph's unscrolled coordinates with the uncommitted-changes row as row 0.
/// [around] when it has to bow past nodes on HEAD's lane rather than run
/// straight down it.
typedef WipLink = ({Offset from, Offset to, bool around});

/// Radius of the dashed ring that marks the uncommitted-changes row.
const wipRingRadius = 7.0;

/// The lane the uncommitted-changes ring sits on: HEAD's, since those changes
/// are made on top of it. With HEAD not loaded, the first lane.
int wipRingLane(WipHead? head) => head?.lane ?? 0;

/// Whether the ring draws its own short strand to the bottom of its row. It
/// does when HEAD is the commit right below, which that strand reaches, and
/// when HEAD is not loaded, as before; otherwise [wipLinkEnds] connects it.
bool wipRingStrand(WipHead? head) => head == null || head.row == 0;

/// Dashed ring for the uncommitted-changes row, on [lane], with a strand down
/// to the bottom of the row when [strand] says the ring draws its own.
class WipRailPainter extends CustomPainter {
  final RailMetrics m;
  final Color color;
  final int lane;
  final bool strand;
  const WipRailPainter({
    required this.m,
    required this.color,
    required this.lane,
    required this.strand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = m.laneX(lane);
    final y = m.nodeY;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;

    if (strand) canvas.drawLine(Offset(x, y), Offset(x, size.height), stroke);

    const dash = 4.0, gap = 3.0;
    final ring = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, y), radius: wipRingRadius));
    for (final metric in ring.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), stroke);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(WipRailPainter old) =>
      old.color != color ||
      old.m.compact != m.compact ||
      old.lane != lane ||
      old.strand != strand;
}

/// Where the connector from the ring to HEAD's node runs; null when the
/// ring's own strand is enough or there is nothing to reach.
///
/// Straight down HEAD's lane when that stretch of lane is clear. Otherwise
/// something sits on the lane above HEAD — a stash made on it, a commit on top
/// of it, another branch's commit on a lane HEAD reuses — and a straight line
/// would run through it, reading as if the changes belonged to them; so the connector leaves
/// the ring's side and enters HEAD's node from the side, bowing past them.
WipLink? wipLinkEnds(RailMetrics m, WipHead? head) {
  if (head == null || wipRingStrand(head)) return null;
  final x = m.laneX(head.lane);
  final headY = (head.row + 1) * m.rowHeight + m.nodeY;
  final r = m.nodeRadius(merge: head.merge);
  return head.clear
      ? (
          from: Offset(x, m.nodeY + wipRingRadius),
          to: Offset(x, headY - r),
          around: false,
        )
      : (
          from: Offset(x + wipRingRadius, m.nodeY),
          to: Offset(x + r, headY),
          around: true,
        );
}

/// The connector's shape: a straight run, or a bow that leaves and enters
/// sideways and keeps between HEAD's lane and the next.
Path wipLinkPath(WipLink link) {
  final path = Path()..moveTo(link.from.dx, link.from.dy);
  if (!link.around) return path..lineTo(link.to.dx, link.to.dy);
  final bow = link.from.dx - wipRingRadius + RailMetrics.laneWidth * 0.75;
  return path
    ..cubicTo(bow, link.from.dy, bow, link.to.dy, link.to.dx, link.to.dy);
}

/// Draws the connector [wipLinkEnds] describes, dashed like the ring, over
/// the rows it crosses. Repaints off [scroll] so scrolling never rebuilds it.
class WipLinkPainter extends CustomPainter {
  final WipLink link;
  final Color color;
  final ScrollController scroll;

  /// Horizontal shift matching the rail's own offset — non-zero when the
  /// branch gutter is drawn to the left of the rail.
  final double dx;

  /// Width of the rail column. Rows clip lanes past it — a rail narrowed in
  /// Columns — and so does the connector, rather than spill over the commit
  /// messages. Null leaves it unclipped across.
  final double? railWidth;

  WipLinkPainter({
    required this.link,
    required this.color,
    required this.scroll,
    this.dx = 0,
    this.railWidth,
  }) : super(repaint: scroll);

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    canvas.save();
    final rail = railWidth;
    canvas.clipRect(
      rail == null
          ? Offset.zero & size
          : Rect.fromLTWH(dx, 0, rail, size.height),
    );
    canvas.translate(dx, -offset);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    const dash = 4.0, gap = 3.0;
    final dashes = Path();
    for (final metric in wipLinkPath(link).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        dashes.addPath(metric.extractPath(d, d + dash), Offset.zero);
      }
    }
    canvas.drawPath(dashes, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(WipLinkPainter old) =>
      old.link != link ||
      old.color != color ||
      old.dx != dx ||
      old.railWidth != railWidth;
}
