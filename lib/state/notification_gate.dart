import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notify/desktop_notifier.dart';
import 'desktop_notifier.dart';
import 'notification_prefs.dart';
import 'window_focus.dart';

/// Whether a notification for [e] on the repo at [repoPath] would be shown
/// right now: the window is unfocused and the settings allow it. Lets callers
/// skip expensive work (building a message, a network call) that would be
/// thrown away.
bool notifyWanted(Ref ref, String repoPath, NotifyEvent e) {
  if (ref.read(windowFocusedProvider)) return false;
  return ref.read(notifyEnabledProvider((repoPath, e)));
}

/// The single door every desktop notification goes through. It only shows
/// one when nobody is looking at the window and the effective setting for the
/// repo allows it.
class NotificationGate {
  final Ref _ref;
  NotificationGate(this._ref);

  /// Shows [n] if allowed. Returns whether it was actually shown; a failing
  /// notifier is swallowed and counts as not shown.
  Future<bool> notify(NotifyEvent e, AppNotification n) async {
    // Callers fire this without awaiting it, so nothing may escape: reading a
    // provider after its container is gone throws, and that would surface as
    // an unhandled async error.
    try {
      final repo = n.target.repoPath;
      // The repo's stored overrides load asynchronously; wait so an override
      // set to off is not missed right after the repo opens. Focus and the
      // settings are checked afterwards, as they may have changed meanwhile.
      await _ref.read(repoNotifyPrefsProvider(repo).notifier).loaded;
      if (!notifyWanted(_ref, repo, e)) return false;
      await _ref.read(desktopNotifierProvider).show(n);
      return true;
    } catch (err) {
      debugPrint('desktop notification failed: $err');
      return false;
    }
  }
}

final notificationGateProvider = Provider<NotificationGate>(
  NotificationGate.new,
);
