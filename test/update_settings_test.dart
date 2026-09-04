import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

void main() {
  test('has not asked about update checks by default', () {
    expect(const AppSettings().updateConsent, '');
    expect(const AppSettings().updateSkippedVersion, '');
    expect(const AppSettings().updateLastCheckMs, 0);
  });

  test('settings saved before this feature existed still load', () {
    final restored = AppSettings.fromJson(const {'themeMode': 'dark'});
    expect(restored.updateConsent, '');
  });

  test('persists the answer and the skipped version', () async {
    final repo = InMemorySettingsRepository();
    final c = SettingsController(repo, const AppSettings());

    c.setUpdateConsent('on');
    c.setUpdateSkippedVersion('1.5.0+16');

    expect(c.state.updateConsent, 'on');
    expect((await repo.load()).updateSkippedVersion, '1.5.0+16');
  });
}
