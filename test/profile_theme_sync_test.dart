import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/profile_theme_sync.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

void main() {
  Profile p(String id) =>
      Profile(id: id, name: id, email: '$id@e.com', colorValue: 0xFF000000);

  test('switching profiles snapshots and restores each theme', () async {
    final kv = InMemoryKeyValueStore();
    final c = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(kv),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);

    final profiles = c.read(profilesProvider.notifier);
    profiles.add(p('alice')); // first becomes active
    profiles.add(p('bob'));
    c.read(profileThemeSyncProvider); // start the sync

    // Alice picks a red accent, then Bob takes over and picks green.
    c.read(settingsProvider.notifier).setAccent(const Color(0xFFD92D20));
    profiles.setActive('bob');
    await Future<void>.delayed(Duration.zero); // let the async snapshot land
    c.read(settingsProvider.notifier).setAccent(const Color(0xFF0E9F6E));

    // Back to Alice: her red accent returns.
    profiles.setActive('alice');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(settingsProvider).accentValue, 0xFFD92D20);

    // And Bob keeps green.
    profiles.setActive('bob');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(settingsProvider).accentValue, 0xFF0E9F6E);
  });
}
