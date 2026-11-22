import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/settings.dart';

void main() {
  test('settings saved with the old usage-data switch still load', () {
    final restored = AppSettings.fromJson(const {
      'themeMode': 'light',
      'telemetryEnabled': true,
    });
    expect(restored.themeMode, ThemeMode.light);
  });

  test('saved settings carry no usage-data switch', () {
    expect(const AppSettings().toJson(), isNot(contains('telemetryEnabled')));
  });
}
