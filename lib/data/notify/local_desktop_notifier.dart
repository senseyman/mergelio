import 'dart:async';

import 'package:local_notifier/local_notifier.dart';

import '../../core/logging.dart';
import '../../domain/notify/desktop_notifier.dart';

/// [DesktopNotifier] backed by the `local_notifier` plugin. Notifications are
/// best-effort: any failure is logged and swallowed, never surfaced.
/// One-time plugin setup. Returns whether notifications can be shown; a failure
/// is logged, not thrown.
Future<bool> initDesktopNotifications() async {
  try {
    await localNotifier.setup(appName: 'Mergelio');
    return true;
  } catch (e, st) {
    appLog.error('notification setup failed', e, st, 'notify');
    return false;
  }
}

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
