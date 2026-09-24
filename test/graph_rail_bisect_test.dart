import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/ui/graph/graph_rail.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';

Commit _c() => Commit(
  sha: 's1',
  message: 'm',
  author: 'a',
  authorEmail: 'a@e',
  date: DateTime(2026),
);

GraphRailPainter _painter({BisectKind? bisect}) => GraphRailPainter(
  c: _c(),
  m: const RailMetrics(),
  palette: const [Colors.red],
  nodeFill: Colors.white,
  // Resolved the same way the commit row resolves it, so what these tests
  // pin is the colour the rail actually paints in a real theme.
  bisectTint: bisect == null ? null : bisectVerdictColor(bisect, _tokens),
);

final _tokens = AppTokens.dark();

/// Records the colour of every circle `paint()` draws, in call order, and
/// no-ops every other [Canvas] method — a fake covering the whole interface
/// via [noSuchMethod], since [Canvas] has far more members than this test
/// cares about.
class _RecordingCanvas implements Canvas {
  final List<Color?> circleColors = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circleColors.add(paint.color);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The colour of the node's centre dot as actually painted — the last of
/// the three circles a non-stash node draws (fill, ring, centre), and the
/// one carrying the verdict tint. Reading this from a real `paint()` call
/// (rather than from a private getter) also catches a `paint()` that stops
/// wiring the tint through, not just a broken mapping.
Color? _paintedNodeColor(BisectKind? bisect) {
  final canvas = _RecordingCanvas();
  _painter(bisect: bisect).paint(canvas, const Size(40, 40));
  return canvas.circleColors.last;
}

void main() {
  test('shouldRepaint is true when the bisect verdict changes', () {
    final old = _painter(bisect: null);
    final next = _painter(bisect: BisectKind.bad);
    expect(next.shouldRepaint(old), isTrue);
  });

  test('shouldRepaint stays false when nothing changes, bisect included', () {
    final old = _painter(bisect: BisectKind.good);
    final next = _painter(bisect: BisectKind.good);
    expect(next.shouldRepaint(old), isFalse);
  });

  test('good, bad and skip each paint a distinct node colour', () {
    final colors = {
      for (final kind in BisectKind.values) kind: _paintedNodeColor(kind),
    };
    expect(
      colors.values.toSet(),
      hasLength(BisectKind.values.length),
      reason: 'every verdict must paint its own colour: $colors',
    );
  });

  test('a verdict paints a colour different from the untinted lane node', () {
    final untinted = _paintedNodeColor(null);
    for (final kind in BisectKind.values) {
      expect(
        _paintedNodeColor(kind),
        isNot(equals(untinted)),
        reason: '$kind must not fall back to the untinted lane colour',
      );
    }
  });
}
