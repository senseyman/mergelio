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

/// Draws dashed connectors from each squash-merged branch tip down to its
/// landing commit, arcing to the right of the rail so they read as inferred
/// links rather than real parent edges. Scrolls with [scrollOffset].
class SquashOverlayPainter extends CustomPainter {
  final List<SquashSegment> segments;
  final RailMetrics metrics;
  final double scrollOffset;
  final int headerRows;
  final List<Color> palette;

  const SquashOverlayPainter({
    required this.segments,
    required this.metrics,
    required this.scrollOffset,
    required this.headerRows,
    required this.palette,
  });

  Offset _node(int index, int lane) => Offset(
    metrics.laneX(lane),
    (index + headerRows) * metrics.rowHeight + metrics.nodeY - scrollOffset,
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in segments) {
      final a = _node(s.fromIndex, s.fromLane);
      final b = _node(s.toIndex, s.toLane);
      if (a.dy < -metrics.rowHeight && b.dy < -metrics.rowHeight) continue;
      if (a.dy > size.height + metrics.rowHeight &&
          b.dy > size.height + metrics.rowHeight) {
        continue;
      }
      // Arc outward to the right so the dashed link stands clear of the lanes.
      final bow = metrics.laneX(s.fromLane.clamp(1, 99)) + 16;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(bow, a.dy, bow, b.dy, b.dx, b.dy);
      _dashed(canvas, path, palette[s.ci % palette.length]);
    }
  }

  void _dashed(Canvas canvas, Path path, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.7);
    const dash = 4.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(SquashOverlayPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.segments != segments ||
      old.headerRows != headerRows;
}
