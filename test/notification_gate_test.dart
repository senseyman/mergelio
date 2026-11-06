import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/notify/desktop_notifier.dart';
import 'package:mergelio/state/desktop_notifier.dart';
import 'package:mergelio/state/notification_gate.dart';
import 'package:mergelio/state/notification_prefs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/window_focus.dart';

import 'support/fake_desktop_notifier.dart';

const _repo = '/work/repo';
const _note = AppNotification(
  title: 'Push finished',
  body: 'main pushed',
  target: NotificationTarget(repoPath: _repo),
);

({ProviderContainer c, FakeDesktopNotifier fake}) _harness({
  bool focused = false,
  bool master = true,
  bool longOps = true,
  KeyValueStore? kv,
}) {
  final fake = FakeDesktopNotifier();
  final c = ProviderContainer(
    overrides: [
      desktopNotifierProvider.overrideWithValue(fake),
      kvStoreProvider.overrideWithValue(kv ?? InMemoryKeyValueStore()),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          AppSettings(notificationsEnabled: master, notifyLongOps: longOps),
        ),
      ),
      windowFocusedProvider.overrideWith((ref) => focused),
    ],
  );
  addTearDown(c.dispose);
  return (c: c, fake: fake);
}

void main() {
  test('focused window shows nothing', () async {
    final h = _harness(focused: true);
    final shown = await h.c
        .read(notificationGateProvider)
        .notify(NotifyEvent.longOps, _note);
    expect(shown, isFalse);
    expect(h.fake.shown, isEmpty);
  });

  test('unfocused with the event off shows nothing', () async {
    final h = _harness(longOps: false);
    final shown = await h.c
        .read(notificationGateProvider)
        .notify(NotifyEvent.longOps, _note);
    expect(shown, isFalse);
    expect(h.fake.shown, isEmpty);
  });

  test('unfocused with the event on shows it once', () async {
    final h = _harness();
    final shown = await h.c
        .read(notificationGateProvider)
        .notify(NotifyEvent.longOps, _note);
    expect(shown, isTrue);
    expect(h.fake.shown, hasLength(1));
    expect(h.fake.shown.single.title, 'Push finished');
    expect(h.fake.shown.single.body, 'main pushed');
  });

  test('master off beats a repo override of on', () async {
    final kv = InMemoryKeyValueStore();
    final h = _harness(master: false, kv: kv);
    await h.c
        .read(repoNotifyPrefsProvider(_repo).notifier)
        .set(NotifyEvent.longOps, NotifyOverride.on);
    final shown = await h.c
        .read(notificationGateProvider)
        .notify(NotifyEvent.longOps, _note);
    expect(shown, isFalse);
    expect(h.fake.shown, isEmpty);
  });

  test('a stored repo override is honoured on first use', () async {
    final kv = InMemoryKeyValueStore();
    await kv.put(
      'notifications:$_repo',
      const RepoNotifyPrefs({NotifyEvent.longOps: NotifyOverride.off}).toJson(),
    );
    final h = _harness(kv: kv);
    final shown = await h.c
        .read(notificationGateProvider)
        .notify(NotifyEvent.longOps, _note);
    expect(shown, isFalse);
    expect(h.fake.shown, isEmpty);
  });

  test('a failing show returns false, and the gate recovers', () async {
    final h = _harness();
    final gate = h.c.read(notificationGateProvider);
    h.fake.throwOnShow = true;
    expect(await gate.notify(NotifyEvent.longOps, _note), isFalse);
    h.fake.throwOnShow = false;
    expect(await gate.notify(NotifyEvent.longOps, _note), isTrue);
    expect(h.fake.shown, hasLength(1));
  });

  test('notifyWanted mirrors the settings without showing', () {
    final probe = Provider.family<bool, bool>(
      (ref, _) => notifyWanted(ref, _repo, NotifyEvent.longOps),
    );
    final on = _harness();
    expect(on.c.read(probe(true)), isTrue);
    final off = _harness(longOps: false);
    expect(off.c.read(probe(true)), isFalse);
    final focused = _harness(focused: true);
    expect(focused.c.read(probe(true)), isFalse);
  });
}
