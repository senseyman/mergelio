import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// The Mergelio brand mark: a circuit "merge-node" — two commit
/// strands with satellite dots converging on a central blue gradient node.
///
/// Vector, theme-adaptive: strands take [strandColor] (defaults to the theme's
/// primary text colour, so it reads on light and dark); the node is always the
/// brand blue gradient.
class MergelioMark extends StatelessWidget {
  final double size;
  final Color? strandColor;

  const MergelioMark({super.key, this.size = 24, this.strandColor});

  @override
  Widget build(BuildContext context) {
    final color = strandColor ?? context.tokens.textPrimary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(color)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color strand;
  _MarkPainter(this.strand);

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinates authored in a 0..100 space; scale to the widget.
    final s = size.width / 100.0;
    Offset p(double x, double y) => Offset(x * s, y * s);

    final stroke = Paint()
      ..color = strand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = strand;

    // arms
    canvas.drawLine(p(50, 45), p(33, 33), stroke);
    canvas.drawLine(p(50, 45), p(67, 33), stroke);
    // legs
    canvas.drawLine(p(45, 52), p(41, 76), stroke);
    canvas.drawLine(p(55, 52), p(59, 76), stroke);
    // satellite connectors
    canvas.drawLine(p(33, 33), p(21, 28), stroke);
    canvas.drawLine(p(33, 33), p(27, 44), stroke);
    canvas.drawLine(p(67, 33), p(79, 28), stroke);
    canvas.drawLine(p(67, 33), p(73, 44), stroke);
    // peak + satellite dots
    canvas.drawCircle(p(33, 33), 6.5 * s, fill);
    canvas.drawCircle(p(67, 33), 6.5 * s, fill);
    for (final d in const [
      [21.0, 28.0],
      [27.0, 44.0],
      [79.0, 28.0],
      [73.0, 44.0],
    ]) {
      canvas.drawCircle(p(d[0], d[1]), 4 * s, fill);
    }

    // central node — blue gradient
    final nodeRect = Rect.fromCircle(center: p(50, 46), radius: 11 * s);
    final nodePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-0.7, -0.8),
        end: Alignment(0.7, 0.9),
        colors: [AppTokens.nodeGradientA, AppTokens.nodeGradientB],
      ).createShader(nodeRect);
    canvas.drawCircle(p(50, 46), 11 * s, nodePaint);
    // highlight
    canvas.drawCircle(
      p(46.5, 42.5),
      3.4 * s,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.strand != strand;
}
