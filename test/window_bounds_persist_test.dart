// The window's position and size survive a restart: the controller writes both
// through to the settings store, and the model carries them across JSON.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

void main() {
  test('a fresh install has no remembered position', () {
    const s = AppSettings();

    expect(s.windowX, isNull);
    expect(s.windowY, isNull);
  });

  test('setWindowBounds persists position and size', () async {
    final repo = InMemorySettingsRepository();
    final c = SettingsController(repo, const AppSettings());

    c.setWindowBounds(120, 60, 1600, 1000);
    await Future<void>.delayed(Duration.zero);

    final stored = await repo.load();
    expect(stored.windowX, 120);
    expect(stored.windowY, 60);
    expect(stored.windowWidth, 1600);
    expect(stored.windowHeight, 1000);
  });

  test('negative coordinates survive (displays left of the primary)', () async {
    final repo = InMemorySettingsRepository();
    final c = SettingsController(repo, const AppSettings());

    c.setWindowBounds(-1400, 200, 1280, 800);
    await Future<void>.delayed(Duration.zero);

    expect((await repo.load()).windowX, -1400);
  });

  test('the position round-trips through JSON', () {
    const s = AppSettings(windowX: 42, windowY: -7);

    final back = AppSettings.fromJson(s.toJson());

    expect(back.windowX, 42);
    expect(back.windowY, -7);
  });

  test('settings saved before the feature existed load with no position', () {
    final back = AppSettings.fromJson({'windowWidth': 1200.0});

    expect(back.windowX, isNull);
    expect(back.windowWidth, 1200.0);
  });
}
