import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notify/desktop_notifier.dart';
import 'notification_gate.dart';
import 'notification_prefs.dart';
import 'settings_controller.dart';

/// The wall clock long-operation timing reads. A provider so tests can move
/// time by hand instead of sleeping.
final opClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

// Lines git prints around a failure that never say what went wrong: where
// it pushed to, fetched from or cloned into, the server's progress chatter,
// hints, and the per-ref summaries of what did update.
const _gitNoisePrefixes = [
  'To ',
  'From ',
  'Cloning into ',
  'hint:',
  'remote:',
  '*',
  '=',
];

// How git relays the server's own explanation, such as a hook's rejection.
const _remotePrefix = 'remote: ';
const _remoteReasons = ['error:', 'fatal:'];

/// The line of git's [text] that best says why it failed, trimmed: enough
/// for a notification body. A server error relayed on a `remote:` line says
/// it most precisely, so the first one wins, without that prefix. Otherwise
/// skips the lines that only say where git talked to or how far it got; when
/// every line is like that, the first non-empty one still beats nothing.
/// Empty when [text] has no visible line.
String gitErrorLine(String text) {
  final lines = text.split('\n');
  for (final raw in lines) {
    final line = raw.trim();
    if (!line.startsWith(_remotePrefix)) continue;
    final reason = line.substring(_remotePrefix.length).trim();
    if (_remoteReasons.any(reason.startsWith)) return reason;
  }
  String? first;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    first ??= line;
    if (_gitNoisePrefixes.any(line.startsWith)) continue;
    return line;
  }
  return first ?? '';
}

/// Notifies that a foreground operation on [repoPath] ended with [body], when
/// it ran from [startedAt] for at least the configured number of seconds.
/// Never throws: a notification problem must not change how the operation
/// itself is reported.
void notifyIfLongOp(
  Ref ref, {
  required DateTime startedAt,
  required String repoPath,
  required String title,
  required String body,
}) {
  try {
    final threshold = Duration(
      seconds: ref.read(settingsProvider).notifyLongOpSeconds,
    );
    if (ref.read(opClockProvider)().difference(startedAt) < threshold) return;
    unawaited(
      ref
          .read(notificationGateProvider)
          .notify(
            NotifyEvent.longOps,
            AppNotification(
              title: title,
              body: body,
              target: NotificationTarget(repoPath: repoPath),
            ),
          ),
    );
  } catch (e) {
    debugPrint('long-operation notification skipped: $e');
  }
}
