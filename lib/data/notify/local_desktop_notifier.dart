import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:local_notifier/local_notifier.dart';

import '../../core/logging.dart';
import '../../domain/notify/desktop_notifier.dart';

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

/// [DesktopNotifier] backed by the `local_notifier` plugin. A notification
/// that fails to show is logged, forgotten and rethrown, so the caller can
/// count it as not shown.
/// Chosen by `desktopNotifierProvider` (state layer) only when
/// [initDesktopNotifications] reported success.
class LocalDesktopNotifier implements DesktopNotifier {
  final _clicks = StreamController<NotificationTarget>.broadcast();
  // A notification's click handler lives on its object, so shown ones are kept
  // referenced until they close.
  final _live = <LocalNotification>{};

  @override
  Stream<NotificationTarget> get clicks => _clicks.stream;

  /// How many shown notifications are still held for their clicks.
  @visibleForTesting
  int get liveCount => _live.length;

  @override
  Future<void> show(AppNotification n) async {
    final note = LocalNotification(title: n.title, body: n.body);
    note.onClick = () {
      if (!_clicks.isClosed) _clicks.add(n.target);
    };
    note.onClose = (_) => _live.remove(note);
    _live.add(note);
    try {
      await note.show();
    } catch (e, st) {
      _live.remove(note);
      appLog.error('notification failed', e, st, 'notify');
      rethrow;
    }
  }

  @override
  void dispose() {
    _live.clear();
    unawaited(_clicks.close());
  }
}
