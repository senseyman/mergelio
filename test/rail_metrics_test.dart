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

    test('rail width uses the fixed width when set, ignoring content', () {
      const fixed = RailMetrics(railFixedWidth: 200);
      expect(fixed.railWidth(0), 200);
      expect(fixed.railWidth(3), 200); // content 92 clipped to fixed
      expect(fixed.railWidth(20), 200); // wide graph clipped to fixed
    });

    test('rail width auto-sizes to content when fixed width is 0', () {
      const auto = RailMetrics(railFixedWidth: 0);
      expect(auto.railWidth(0), 32);
      expect(auto.railWidth(3), 92);
    });

    test('branch width defaults to 116 and is configurable', () {
      expect(m.branchWidth, 116);
      expect(const RailMetrics(branchWidth: 200).branchWidth, 200);
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
