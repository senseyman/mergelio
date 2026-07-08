import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

void main() {
  late SettingsController c;
  setUp(() {
    c = SettingsController(InMemorySettingsRepository(), const AppSettings());
  });

  test('default zoom is 100%', () => expect(c.state.uiScale, 1.0));

  test('zoomIn/zoomOut step by 10% and clamp to 100–200%', () {
    c.zoomIn();
    expect(c.state.uiScale, closeTo(1.1, 1e-9));
    // Clamp at the top.
    for (var i = 0; i < 20; i++) {
      c.zoomIn();
    }
    expect(c.state.uiScale, 2.0);
    // Clamp at the bottom.
    for (var i = 0; i < 20; i++) {
      c.zoomOut();
    }
    expect(c.state.uiScale, 1.0);
  });

  test('zoomReset returns to 100%', () {
    c.zoomIn();
    c.zoomIn();
    c.zoomReset();
    expect(c.state.uiScale, 1.0);
  });

  test('setUiScale clamps out-of-range values', () {
    c.setUiScale(5.0);
    expect(c.state.uiScale, 2.0);
    c.setUiScale(0.2);
    expect(c.state.uiScale, 1.0);
  });
}
