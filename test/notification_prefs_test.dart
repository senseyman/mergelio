import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/notification_prefs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

Override _settingsOverride() => settingsProvider.overrideWith(
  (ref) =>
      SettingsController(InMemorySettingsRepository(), const AppSettings()),
);

AppSettings _settings(bool master, bool global, NotifyEvent e) {
  final s = AppSettings(notificationsEnabled: master);
  return switch (e) {
    NotifyEvent.longOps => s.copyWith(notifyLongOps: global),
    NotifyEvent.ci => s.copyWith(notifyCi: global),
    NotifyEvent.pullRequests => s.copyWith(notifyPullRequests: global),
  };
}

void main() {
  group('effectiveNotify', () {
    for (final e in NotifyEvent.values) {
      for (final master in [false, true]) {
        for (final global in [false, true]) {
          for (final o in NotifyOverride.values) {
            final expected = !master
                ? false
                : switch (o) {
                    NotifyOverride.on => true,
                    NotifyOverride.off => false,
                    NotifyOverride.inherit => global,
                  };
            test('${e.name} master=$master global=$global ${o.name}', () {
              expect(
                effectiveNotify(_settings(master, global, e), e, o),
                expected,
              );
            });
          }
        }
      }
    }
  });

  group('RepoNotifyPrefs.fromJson', () {
    test('null is all inherit', () {
      final p = RepoNotifyPrefs.fromJson(null);
      for (final e in NotifyEvent.values) {
        expect(p.of(e), NotifyOverride.inherit);
      }
    });

    test('garbled is all inherit', () {
      final p = RepoNotifyPrefs.fromJson('{');
      for (final e in NotifyEvent.values) {
        expect(p.of(e), NotifyOverride.inherit);
      }
    });

    test('a bad value falls back to inherit, a good key survives', () {
      final p = RepoNotifyPrefs.fromJson('{"ci":"on","longOps":"bogus"}');
      expect(p.of(NotifyEvent.ci), NotifyOverride.on);
      expect(p.of(NotifyEvent.longOps), NotifyOverride.inherit);
      expect(p.of(NotifyEvent.pullRequests), NotifyOverride.inherit);
    });

    test('a non-object payload is all inherit', () {
      final p = RepoNotifyPrefs.fromJson('[1]');
      expect(p.of(NotifyEvent.ci), NotifyOverride.inherit);
    });

    test('toJson stores only on/off under the event names', () {
      final p = const RepoNotifyPrefs()
          .copyWith(NotifyEvent.pullRequests, NotifyOverride.off)
          .copyWith(NotifyEvent.longOps, NotifyOverride.on)
          .copyWith(NotifyEvent.ci, NotifyOverride.inherit);
      expect(p.toJson(), '{"longOps":"on","pullRequests":"off"}');
      final back = RepoNotifyPrefs.fromJson(p.toJson());
      expect(back.of(NotifyEvent.longOps), NotifyOverride.on);
      expect(back.of(NotifyEvent.pullRequests), NotifyOverride.off);
      expect(back.of(NotifyEvent.ci), NotifyOverride.inherit);
    });
  });

  group('repoNotifyPrefsProvider', () {
    test('set writes through and a new container reads it back', () async {
      final store = InMemoryKeyValueStore();
      final c1 = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c1.dispose);
      expect(
        c1.read(repoNotifyPrefsProvider('/r')).of(NotifyEvent.ci),
        NotifyOverride.inherit,
      );
      await c1
          .read(repoNotifyPrefsProvider('/r').notifier)
          .set(NotifyEvent.ci, NotifyOverride.on);
      expect(
        c1.read(repoNotifyPrefsProvider('/r')).of(NotifyEvent.ci),
        NotifyOverride.on,
      );
      expect(await store.get('notifications:/r'), isNotNull);

      final c2 = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c2.dispose);
      c2.read(repoNotifyPrefsProvider('/r'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        c2.read(repoNotifyPrefsProvider('/r')).of(NotifyEvent.ci),
        NotifyOverride.on,
      );
      expect(
        c2.read(repoNotifyPrefsProvider('/other')).of(NotifyEvent.ci),
        NotifyOverride.inherit,
      );
    });

    test('a set made before the load lands is not overwritten by it', () async {
      final store = InMemoryKeyValueStore();
      await store.put('notifications:/r', '{"ci":"off"}');
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      final n = c.read(repoNotifyPrefsProvider('/r').notifier);
      await n.set(NotifyEvent.longOps, NotifyOverride.on);
      await Future<void>.delayed(Duration.zero);
      final p = c.read(repoNotifyPrefsProvider('/r'));
      expect(p.of(NotifyEvent.longOps), NotifyOverride.on);
      expect(p.of(NotifyEvent.ci), NotifyOverride.off);
    });
  });

  group('AppSettings notification fields', () {
    test('defaults', () {
      const s = AppSettings();
      expect(s.notificationsEnabled, isFalse);
      expect(s.notifyLongOps, isFalse);
      expect(s.notifyCi, isFalse);
      expect(s.notifyPullRequests, isFalse);
      expect(s.notifyLongOpSeconds, 10);
      expect(kNotifyLongOpChoices, [5, 10, 30, 60]);
    });

    test('json round-trip keeps the fields', () {
      final s = const AppSettings().copyWith(
        notificationsEnabled: true,
        notifyCi: true,
        notifyLongOpSeconds: 30,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.notificationsEnabled, isTrue);
      expect(back.notifyCi, isTrue);
      expect(back.notifyLongOps, isFalse);
      expect(back.notifyLongOpSeconds, 30);
    });
  });

  group('notifyEnabledProvider and setters', () {
    test('combines settings with the repo override', () async {
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          _settingsOverride(),
        ],
      );
      addTearDown(c.dispose);
      final s = c.read(settingsProvider.notifier);
      const key = ('/r', NotifyEvent.ci);
      expect(c.read(notifyEnabledProvider(key)), isFalse);
      s.setNotificationsEnabled(true);
      s.setNotify(NotifyEvent.ci, true);
      expect(c.read(notifyEnabledProvider(key)), isTrue);
      await c
          .read(repoNotifyPrefsProvider('/r').notifier)
          .set(NotifyEvent.ci, NotifyOverride.off);
      expect(c.read(notifyEnabledProvider(key)), isFalse);
      s.setNotificationsEnabled(false);
      await c
          .read(repoNotifyPrefsProvider('/r').notifier)
          .set(NotifyEvent.ci, NotifyOverride.on);
      expect(c.read(notifyEnabledProvider(key)), isFalse);
    });

    test('setNotify touches only its own event; seconds clamp 1..3600', () {
      final c = ProviderContainer(overrides: [_settingsOverride()]);
      addTearDown(c.dispose);
      final s = c.read(settingsProvider.notifier);
      s.setNotify(NotifyEvent.pullRequests, true);
      var st = c.read(settingsProvider);
      expect(st.notifyPullRequests, isTrue);
      expect(st.notifyCi, isFalse);
      expect(st.notifyLongOps, isFalse);
      s.setNotifyLongOpSeconds(0);
      expect(c.read(settingsProvider).notifyLongOpSeconds, 1);
      s.setNotifyLongOpSeconds(99999);
      expect(c.read(settingsProvider).notifyLongOpSeconds, 3600);
      s.setNotifyLongOpSeconds(30);
      expect(c.read(settingsProvider).notifyLongOpSeconds, 30);
    });
  });
}
