import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

void main() {
  test('applySavedTheme survives a blob whose colours are not strings', () {
    // Decodes as JSON but fails the `as String` cast on branch colours — a
    // TypeError, not a FormatException, so a narrow catch would crash.
    const corrupt =
        '{"name":"x","theme":"dark","accent":"#112233","branchColors":[1,2]}';
    final c = SettingsController(
      InMemorySettingsRepository(),
      const AppSettings(savedThemes: {'bad': corrupt}),
    );
    final before = c.state.accentValue;

    expect(() => c.applySavedTheme('bad'), returnsNormally);
    expect(c.state.accentValue, before);
  });

  test('applySavedTheme survives an invalid hex colour', () {
    const corrupt =
        '{"name":"x","theme":"dark","accent":"#zzzzzz","branchColors":[]}';
    final c = SettingsController(
      InMemorySettingsRepository(),
      const AppSettings(savedThemes: {'bad': corrupt}),
    );

    expect(() => c.applySavedTheme('bad'), returnsNormally);
  });
}
