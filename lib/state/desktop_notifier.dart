import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notify/local_desktop_notifier.dart';
import '../domain/notify/desktop_notifier.dart';
import 'settings_controller.dart';

/// Sets the notification plugin up; overridable so tests never touch it.
final desktopNotificationsInitProvider = Provider<Future<bool> Function()>(
  (_) => initDesktopNotifications,
);

// Runs the plugin setup the first time it is asked for and keeps the answer,
// so switching notifications off and on again does not set it up twice.
final _desktopNotificationsSetupProvider = FutureProvider<bool>(
  (ref) => ref.read(desktopNotificationsInitProvider)(),
);

/// Whether notifications are on and the plugin finished setup. The plugin is
/// set up only once notifications are first switched on: on Windows setup
/// adds a Start-menu shortcut, which a user who never wants notifications
/// should not get.
final desktopNotificationsReadyProvider = Provider<bool>((ref) {
  final on = ref.watch(settingsProvider.select((s) => s.notificationsEnabled));
  if (!on) return false;
  return ref.watch(_desktopNotificationsSetupProvider).valueOrNull ?? false;
});

final desktopNotifierProvider = Provider<DesktopNotifier>((ref) {
  final DesktopNotifier notifier = ref.watch(desktopNotificationsReadyProvider)
      ? LocalDesktopNotifier()
      : NullDesktopNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});
