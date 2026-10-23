// Where the uncommitted-changes row's connector runs: from its ring, in the
// top row, down HEAD's lane to HEAD's node.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';
import 'package:mergelio/ui/graph/wip_link.dart';

void main() {
  const m = RailMetrics();

  test('runs straight down HEAD\'s lane when nothing sits on it above', () {
    final link = wipLinkEnds(m, (row: 2, lane: 1, merge: false, clear: true))!;

    final x = m.laneX(1);
    expect(link.around, isFalse);
    expect(link.from, Offset(x, m.nodeY + wipRingRadius));
    // HEAD's row sits below the uncommitted-changes row, hence the + 1.
    expect(
      link.to,
      Offset(x, 3 * m.rowHeight + m.nodeY - m.nodeRadius(merge: false)),
    );
  });

  test('goes around what sits on HEAD\'s lane above it', () {
    // A stash made on HEAD, or a commit on top of it, takes HEAD's lane
    // above; a straight line would run through its node.
    final link = wipLinkEnds(m, (row: 1, lane: 0, merge: false, clear: false))!;

    final x = m.laneX(0);
    expect(link.around, isTrue);
    expect(link.from, Offset(x + wipRingRadius, m.nodeY));
    expect(
      link.to,
      Offset(x + m.nodeRadius(merge: false), 2 * m.rowHeight + m.nodeY),
    );
  });

  test('stops at the larger edge of a merge node', () {
    final ends = wipLinkEnds(m, (row: 1, lane: 0, merge: true, clear: true))!;

    expect(ends.to.dy, 2 * m.rowHeight + m.nodeY - m.nodeRadius(merge: true));
  });

  test('follows the compact row height', () {
    const compact = RailMetrics(compact: true);
    final ends = wipLinkEnds(compact, (
      row: 1,
      lane: 0,
      merge: false,
      clear: true,
    ))!;

    expect(
      ends.to.dy,
      2 * compact.rowHeight + compact.nodeY - compact.nodeRadius(merge: false),
    );
  });

  test('is not needed when HEAD is the commit right below', () {
    // The ring's own short strand reaches it.
    expect(
      wipLinkEnds(m, (row: 0, lane: 0, merge: false, clear: true)),
      isNull,
    );
  });

  test('has nothing to reach when HEAD is not loaded', () {
    expect(wipLinkEnds(m, null), isNull);
  });

  group('the ring', () {
    test('sits on HEAD\'s lane', () {
      expect(wipRingLane((row: 4, lane: 2, merge: false, clear: true)), 2);
    });

    test('falls back to the first lane when HEAD is not loaded', () {
      expect(wipRingLane(null), 0);
    });

    test('draws its own strand down only when nothing else connects it', () {
      expect(
        wipRingStrand((row: 0, lane: 0, merge: false, clear: true)),
        isTrue,
      );
      expect(wipRingStrand(null), isTrue);
      expect(
        wipRingStrand((row: 3, lane: 1, merge: false, clear: true)),
        isFalse,
      );
    });
  });

  group('painting', () {
    const color = Color(0xFFFFAA00);

    /// [painter] as something the `paints` matcher can run: a row-sized
    /// paint of it.
    void Function(Canvas) drawn(CustomPainter painter) =>
        (canvas) => painter.paint(canvas, Size(200, m.rowHeight * 4));

    test('the ring draws its strand only when asked to', () {
      WipRailPainter ring({required bool strand}) =>
          WipRailPainter(m: m, color: color, lane: 1, strand: strand);
      final x = m.laneX(1);

      expect(drawn(ring(strand: true)), paints..line(p1: Offset(x, m.nodeY)));
      expect(drawn(ring(strand: false)), isNot(paints..line()));
    });

    test('the connector is dashed all the way from the ring to the node', () {
      final link = wipLinkEnds(m, (
        row: 2,
        lane: 1,
        merge: false,
        clear: true,
      ))!;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      final path = wipLinkPath(link);
      final metric = path.computeMetrics().single;
      expect(metric.getTangentForOffset(0)!.position, link.from);
      expect(metric.getTangentForOffset(metric.length)!.position, link.to);
      expect(
        drawn(WipLinkPainter(link: link, color: color, scroll: scroll)),
        paints..path(),
      );
    });

    test('a connector going around keeps clear of nodes on HEAD\'s lane', () {
      final link = wipLinkEnds(m, (
        row: 3,
        lane: 0,
        merge: false,
        clear: false,
      ))!;
      final metric = wipLinkPath(link).computeMetrics().single;
      final x = m.laneX(0);

      // Every row it passes, it stays right of the largest node — a stash's
      // square — and left of the next lane.
      for (var row = 1; row <= 3; row++) {
        final y = row * m.rowHeight + m.nodeY;
        var closest = double.infinity;
        Offset? at;
        for (var d = 0.0; d <= metric.length; d += 0.5) {
          final p = metric.getTangentForOffset(d)!.position;
          if ((p.dy - y).abs() < closest) {
            closest = (p.dy - y).abs();
            at = p;
          }
        }
        expect(at!.dx - x, greaterThan(m.nodeRadius(merge: true) * 1.2));
        expect(at.dx, lessThan(m.laneX(1) - 3));
      }
      expect(metric.getTangentForOffset(0)!.position, link.from);
      expect(metric.getTangentForOffset(metric.length)!.position, link.to);
    });
    test('the connector stays inside the rail, as the rows do', () {
      // A rail narrowed in Columns clips lanes past its width; a connector on
      // one of those lanes must not spill over the commit messages.
      final link = wipLinkEnds(m, (
        row: 3,
        lane: 5,
        merge: false,
        clear: true,
      ))!;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      expect(
        drawn(
          WipLinkPainter(
            link: link,
            color: color,
            scroll: scroll,
            dx: 116,
            railWidth: 60,
          ),
        ),
        paints..clipRect(rect: const Rect.fromLTWH(116, 0, 60, 52 * 4)),
      );
    });
  });
}
