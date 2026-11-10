import 'dart:async';

import 'package:mergelio/domain/notify/desktop_notifier.dart';

/// Records what would have been shown and lets a test simulate a click.
class FakeDesktopNotifier implements DesktopNotifier {
  final List<AppNotification> shown = [];
  bool throwOnShow = false;
  final _clicks = StreamController<NotificationTarget>.broadcast();

  @override
  Stream<NotificationTarget> get clicks => _clicks.stream;

  void click(NotificationTarget t) {
    if (!_clicks.isClosed) _clicks.add(t);
  }

  @override
  Future<void> show(AppNotification n) async {
    if (throwOnShow) throw Exception('show failed');
    shown.add(n);
  }

  @override
  void dispose() {
    unawaited(_clicks.close());
  }
}
