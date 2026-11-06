import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/notify/local_desktop_notifier.dart';
import 'package:mergelio/state/desktop_notifier.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/notify/desktop_notifier.dart';

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

  test('provider yields a no-op notifier until the plugin is ready', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(desktopNotifierProvider), isA<NullDesktopNotifier>());
  });

  test('provider yields the plugin notifier once ready', () {
    final c = ProviderContainer(
      overrides: [desktopNotificationsReadyProvider.overrideWithValue(true)],
    );
    addTearDown(c.dispose);
    expect(c.read(desktopNotifierProvider), isA<LocalDesktopNotifier>());
  });

  test('FakeDesktopNotifier click after dispose is ignored', () {
    final f = FakeDesktopNotifier()..dispose();
    f.click(target);
  });
}
