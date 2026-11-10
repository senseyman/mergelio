import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/notify/local_desktop_notifier.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/desktop_notifier.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/notify/desktop_notifier.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

import 'support/fake_desktop_notifier.dart';

void main() {
  const target = NotificationTarget(
    repoPath: '/r',
    kind: ForgeKind.github,
    prNumber: 7,
    targetBranch: 'main',
  );
  const note = AppNotification(title: 't', body: 'b', target: target);

  test('NullDesktopNotifier show completes and clicks emits nothing', () async {
    final n = NullDesktopNotifier();
    final seen = <NotificationTarget>[];
    final sub = n.clicks.listen(seen.add);
    await n.show(note);
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
    await sub.cancel();
    n.dispose();
  });

  test('NotificationTarget compares by value', () {
    expect(
      target,
      const NotificationTarget(
        repoPath: '/r',
        kind: ForgeKind.github,
        prNumber: 7,
        targetBranch: 'main',
      ),
    );
    expect(
      target.hashCode,
      const NotificationTarget(
        repoPath: '/r',
        kind: ForgeKind.github,
        prNumber: 7,
        targetBranch: 'main',
      ).hashCode,
    );
    expect(target, isNot(const NotificationTarget(repoPath: '/r')));
    expect(
      const NotificationTarget(repoPath: '/r'),
      const NotificationTarget(repoPath: '/r'),
    );
  });

  test('FakeDesktopNotifier records shown and emits clicks', () async {
    final f = FakeDesktopNotifier();
    final seen = <NotificationTarget>[];
    final sub = f.clicks.listen(seen.add);
    await f.show(note);
    expect(f.shown, [note]);
    f.click(target);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [target]);
    await sub.cancel();
    f.dispose();
  });

  test('FakeDesktopNotifier throws on show when asked', () async {
    final f = FakeDesktopNotifier()..throwOnShow = true;
    await expectLater(f.show(note), throwsA(isA<Exception>()));
    expect(f.shown, isEmpty);
    f.dispose();
  });

  group('plugin setup', () {
    late int inits;
    late bool initResult;
    ProviderContainer container({required bool enabled}) {
      inits = 0;
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              AppSettings(notificationsEnabled: enabled),
            ),
          ),
          desktopNotificationsInitProvider.overrideWithValue(() async {
            inits++;
            return initResult;
          }),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() => initResult = true);

    test('with notifications off the plugin is never set up', () async {
      final c = container(enabled: false);
      expect(c.read(desktopNotifierProvider), isA<NullDesktopNotifier>());
      await Future<void>.delayed(Duration.zero);
      expect(c.read(desktopNotifierProvider), isA<NullDesktopNotifier>());
      expect(inits, 0);
    });

    test('turning notifications on sets the plugin up once', () async {
      final c = container(enabled: false);
      c.read(desktopNotifierProvider);
      final s = c.read(settingsProvider.notifier);
      s.setNotificationsEnabled(true);
      expect(c.read(desktopNotifierProvider), isA<NullDesktopNotifier>());
      await Future<void>.delayed(Duration.zero);
      expect(c.read(desktopNotifierProvider), isA<LocalDesktopNotifier>());

      s.setNotificationsEnabled(false);
      expect(c.read(desktopNotifierProvider), isA<NullDesktopNotifier>());
      // Long enough off for anything no longer listened to to be disposed.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      s.setNotificationsEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(desktopNotifierProvider), isA<LocalDesktopNotifier>());
      expect(inits, 1);
    });

    test('a failed setup leaves the no-op notifier', () async {
      initResult = false;
      final c = container(enabled: true);
      c.read(desktopNotifierProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(desktopNotifierProvider), isA<NullDesktopNotifier>());
      expect(inits, 1);
    });
  });

  test('FakeDesktopNotifier click after dispose is ignored', () {
    final f = FakeDesktopNotifier()..dispose();
    f.click(target);
  });
}
