import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';

void main() {
  group('RailMetrics', () {
    const m = RailMetrics();

    test('lane x positions step by lane width from the left pad', () {
      expect(m.laneX(0), 16);
      expect(m.laneX(1), 36);
      expect(m.laneX(2), 56);
    });

    test('rail width fits the widest lane plus padding on both sides', () {
      expect(m.railWidth(0), 32);
      expect(m.railWidth(1), 52);
      expect(m.railWidth(3), 92);
    });

    test('node sits at the vertical centre of the row', () {
      expect(m.nodeY, 26);
      expect(const RailMetrics(compact: true).nodeY, 17);
    });

    test('row height is 52, compact 34', () {
      expect(m.rowHeight, 52);
      expect(const RailMetrics(compact: true).rowHeight, 34);
    });

    test('merge nodes are larger than regular nodes', () {
      expect(
        m.nodeRadius(merge: true),
        greaterThan(m.nodeRadius(merge: false)),
      );
      expect(
        m.centerRadius(merge: true),
        greaterThan(m.centerRadius(merge: false)),
      );
    });
  });
}
