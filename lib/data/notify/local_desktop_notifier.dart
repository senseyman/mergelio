import 'dart:async';

import 'package:local_notifier/local_notifier.dart';

import '../../core/logging.dart';
import '../../domain/notify/desktop_notifier.dart';

/// [DesktopNotifier] backed by the `local_notifier` plugin. Notifications are
/// best-effort: any failure is logged and swallowed, never surfaced.
bool _pluginReady = false;

/// One-time plugin setup. Returns normally even when it fails; the notifier
/// provider then falls back to a no-op notifier.
Future<void> initDesktopNotifications() async {
  try {
    await localNotifier.setup(appName: 'Mergelio');
    _pluginReady = true;
  } catch (e, st) {
    appLog.error('notification setup failed', e, st, 'notify');
  }
}

/// Whether [initDesktopNotifications] succeeded.
bool get desktopNotificationsReady => _pluginReady;

class LocalDesktopNotifier implements DesktopNotifier {
  final _clicks = StreamController<NotificationTarget>.broadcast();
  // A notification's click handler lives on its object, so shown ones are kept
  // referenced until they close.
  final _live = <LocalNotification>{};

  @override
  Stream<NotificationTarget> get clicks => _clicks.stream;

  @override
  Future<void> show(AppNotification n) async {
    try {
      final note = LocalNotification(title: n.title, body: n.body);
      note.onClick = () {
        if (!_clicks.isClosed) _clicks.add(n.target);
      };
      note.onClose = (_) => _live.remove(note);
      _live.add(note);
      await note.show();
    } catch (e, st) {
      appLog.error('notification failed', e, st, 'notify');
    }
  }

  @override
  void dispose() {
    _live.clear();
    unawaited(_clicks.close());
  }
}
