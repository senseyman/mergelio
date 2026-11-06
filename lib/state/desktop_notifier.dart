import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notify/local_desktop_notifier.dart';
import '../domain/notify/desktop_notifier.dart';

/// Whether the notification plugin finished setup; overridden at launch.
final desktopNotificationsReadyProvider = Provider<bool>((_) => false);

final desktopNotifierProvider = Provider<DesktopNotifier>((ref) {
  final DesktopNotifier notifier = ref.watch(desktopNotificationsReadyProvider)
      ? LocalDesktopNotifier()
      : NullDesktopNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});
