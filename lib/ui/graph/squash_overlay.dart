import 'package:flutter/material.dart';

import '../../domain/git/models.dart';
import 'rail_metrics.dart';

/// A squash link resolved to the row indices of its endpoints.
class SquashSegment {
  final int fromIndex;
  final int toIndex;
  final int fromLane;
  final int toLane;
  final int ci;
  const SquashSegment({
    required this.fromIndex,
    required this.toIndex,
    required this.fromLane,
    required this.toLane,
    required this.ci,
  });
}

/// Keeps only the links whose both endpoints are present in [rowIndex]
/// (sha → row index), pairing each with lane/colour info from [laneOf].
List<SquashSegment> resolveSquashSegments(
  List<SquashLink> links,
  Map<String, int> rowIndex, {
  Map<String, ({int lane, int ci})> laneOf = const {},
}) {
  final out = <SquashSegment>[];
  for (final l in links) {
    final from = rowIndex[l.fromSha];
    final to = rowIndex[l.toSha];
    if (from == null || to == null) continue;
    final f = laneOf[l.fromSha];
    final t = laneOf[l.toSha];
    out.add(
      SquashSegment(
        fromIndex: from,
        toIndex: to,
        fromLane: f?.lane ?? 0,
        toLane: t?.lane ?? 0,
        ci: f?.ci ?? 0,
      ),
    );
  }
  return out;
}

/// All dashes of one colour merged into a single [Path] (in un-scrolled canvas
/// coordinates), so the paint loop is one `drawPath` per colour instead of one
/// per dash.
class SquashDash {
  final Path path;
  final Color color;
  const SquashDash(this.path, this.color);
}

/// Builds the dashed connector geometry for [segments] once, grouping all
/// dashes by colour into a single combined path each. Expensive
/// (`computeMetrics`/`extractPath`) — cache the result and only rebuild when
/// the segments or metrics change.
List<SquashDash> buildSquashDashes(
  List<SquashSegment> segments,
  RailMetrics metrics,
  int headerRows,
  List<Color> palette,
) {
  const dash = 4.0, gap = 3.0;
  Offset node(int index, int lane) => Offset(
    metrics.laneX(lane),
    (index + headerRows) * metrics.rowHeight + metrics.nodeY,
  );
  final byColor = <int, ({Color color, Path path})>{};
  for (final s in segments) {
    final a = node(s.fromIndex, s.fromLane);
    final b = node(s.toIndex, s.toLane);
    final bow = metrics.laneX(s.fromLane.clamp(1, 99)) + 16;
    final curve = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(bow, a.dy, bow, b.dy, b.dx, b.dy);
    final color = palette[s.ci % palette.length].withValues(alpha: 0.7);
    final combined = byColor
        .putIfAbsent(color.toARGB32(), () => (color: color, path: Path()))
        .path;
    for (final metric in curve.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        combined.addPath(metric.extractPath(d, d + dash), Offset.zero);
        d += dash + gap;
      }
    }
  }
  return [for (final e in byColor.values) SquashDash(e.path, e.color)];
}

/// Draws the pre-built dashed connectors, translated by the scroll offset.
/// Repaints directly off the [scroll] controller ([CustomPainter.repaint]) so
/// scrolling never rebuilds the widget — only the render object repaints, and
/// the paint loop is a handful of cheap `drawPath` calls (one per colour).
class SquashDashPainter extends CustomPainter {
  final List<SquashDash> dashes;
  final ScrollController scroll;
  SquashDashPainter({required this.dashes, required this.scroll})
    : super(repaint: scroll);

  @override
  void paint(Canvas canvas, Size size) {
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    canvas.save();
    // Clip to the paint bounds: the dashes are drawn in scrolled coordinates,
    // so off-screen ones (above/below) must not bleed outside the graph.
    canvas.clipRect(Offset.zero & size);
    canvas.translate(0, -offset);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final d in dashes) {
      paint.color = d.color;
      canvas.drawPath(d.path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SquashDashPainter old) => !identical(old.dashes, dashes);
}
