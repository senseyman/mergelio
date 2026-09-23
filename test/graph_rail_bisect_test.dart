import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  bisect: bisect,
);

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
}
