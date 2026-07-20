import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

void main() {
  late SettingsController c;

  setUp(() {
    c = SettingsController(InMemorySettingsRepository(), const AppSettings());
  });

  group('graph column widths', () {
    test('defaults: branch 116, rail width 0 (auto)', () {
      const s = AppSettings();
      expect(s.graphBranchWidth, 116);
      expect(s.graphRailWidth, 0);
    });

    test('setGraphBranchWidth clamps to 40..400', () {
      c.setGraphBranchWidth(150);
      expect(c.state.graphBranchWidth, 150);
      c.setGraphBranchWidth(10);
      expect(c.state.graphBranchWidth, 40);
      c.setGraphBranchWidth(9999);
      expect(c.state.graphBranchWidth, 400);
    });

    test('setGraphRailWidth: 0 stays auto, positive clamps to 24..1200', () {
      c.setGraphRailWidth(250);
      expect(c.state.graphRailWidth, 250);
      c.setGraphRailWidth(0); // reset to auto
      expect(c.state.graphRailWidth, 0);
      c.setGraphRailWidth(-50); // any non-positive means auto
      expect(c.state.graphRailWidth, 0);
      c.setGraphRailWidth(10); // dragged small → floor 24
      expect(c.state.graphRailWidth, 24);
      c.setGraphRailWidth(9999);
      expect(c.state.graphRailWidth, 1200);
    });

    test('widths survive a JSON round-trip', () {
      final json = const AppSettings(
        graphBranchWidth: 180,
        graphRailWidth: 220,
      ).toJson();
      final back = AppSettings.fromJson(json);
      expect(back.graphBranchWidth, 180);
      expect(back.graphRailWidth, 220);
    });

    test('absent JSON keys fall back to defaults', () {
      final back = AppSettings.fromJson(<String, dynamic>{});
      expect(back.graphBranchWidth, 116);
      expect(back.graphRailWidth, 0);
    });
  });
}
