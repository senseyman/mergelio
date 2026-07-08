import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/theme_io.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

void main() {
  late SettingsController c;

  setUp(() {
    c = SettingsController(InMemorySettingsRepository(), const AppSettings());
  });

  final base = List.generate(8, (i) => 0xFF000000 | (i * 0x111111));

  test('applyTheme sets mode, accent and branch overrides', () {
    c.applyTheme(
      ThemeSpec(
        name: 'x',
        mode: 'light',
        accent: 0xFF123456,
        branchColors: base,
      ),
    );
    expect(c.state.themeMode, ThemeMode.light);
    expect(c.state.accentValue, 0xFF123456);
    expect(c.state.branchColorOverrides['0'], base[0]);
    expect(c.state.branchColorOverrides['7'], base[7]);
  });

  test('currentTheme reflects overrides over the base palette', () {
    c.setBranchColor(2, const Color(0xFFABCDEF));
    final spec = c.currentTheme('t', base);
    expect(spec.branchColors[2], 0xFFABCDEF);
    expect(spec.branchColors[0], base[0]); // untouched → base
  });

  test('saveTheme stores a re-applicable JSON blob', () {
    c.setAccent(const Color(0xFF00FF00));
    c.saveTheme('mine', base);
    final blob = c.state.savedThemes['mine']!;
    expect(ThemeSpec.decode(blob).accent, 0xFF00FF00);
  });

  test('a full export → applyTheme round-trips the colours', () {
    c.setAccent(const Color(0xFF7C8CFF));
    c.setBranchColor(0, const Color(0xFF4C5BF5));
    final exported = c.currentTheme('e', base).encode();

    final c2 = SettingsController(
      InMemorySettingsRepository(),
      const AppSettings(),
    );
    c2.applyTheme(ThemeSpec.decode(exported));
    expect(c2.state.accentValue, 0xFF7C8CFF);
    expect(c2.state.branchColorOverrides['0'], 0xFF4C5BF5);
  });

  test('applySavedTheme re-applies a saved theme; delete forgets it', () {
    c.setAccent(const Color(0xFF00FF00));
    c.saveTheme('mine', base);
    // Change accent, then re-apply the saved one.
    c.setAccent(const Color(0xFF111111));
    c.applySavedTheme('mine');
    expect(c.state.accentValue, 0xFF00FF00);

    c.deleteSavedTheme('mine');
    expect(c.state.savedThemes.containsKey('mine'), isFalse);
    // Applying a now-unknown theme is a no-op (no throw).
    c.applySavedTheme('mine');
    expect(c.state.accentValue, 0xFF00FF00);
  });

  test('setThemeMode(system) round-trips through settings', () {
    c.setThemeMode(ThemeMode.system);
    expect(c.state.themeMode, ThemeMode.system);
  });
}
