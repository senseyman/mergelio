// The local_notifier adapter, with the plugin's channel answered in Dart so
// no platform notification is shown.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/notify/local_desktop_notifier.dart';
import 'package:mergelio/domain/notify/desktop_notifier.dart';

const _channel = MethodChannel('local_notifier');
const _note = AppNotification(
  title: 'repo',
  body: 'Push finished',
  target: NotificationTarget(repoPath: '/work/repo'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    // Linux and Windows refuse to notify before setup; answer it here too.
    messenger.setMockMethodCallHandler(_channel, (call) async => true);
    expect(await initDesktopNotifications(), isTrue);
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('a shown notification stays referenced for its click', () async {
    final n = LocalDesktopNotifier();
    addTearDown(n.dispose);

    await n.show(_note);

    expect(n.liveCount, 1);
  });

  test('a failed show is forgotten and reported to the caller', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'notify') {
        throw PlatformException(code: 'denied');
      }
      return true;
    });
    final n = LocalDesktopNotifier();
    addTearDown(n.dispose);

    await expectLater(n.show(_note), throwsA(isA<PlatformException>()));

    expect(n.liveCount, 0);
  });
}
