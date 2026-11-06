import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../domain/notify/desktop_notifier.dart';
import 'desktop_notifier.dart';
import 'open_review.dart';
import 'workspace.dart';

/// Brings the app window to the front; overridable so tests do not need a
/// native window.
final windowRaiseProvider = Provider<Future<void> Function()>(
  (_) => () async {
    await windowManager.show();
    await windowManager.focus();
  },
);

/// Sends a clicked notification to its repo tab and, when it names a pull
/// request, to that request's review. A repo that is no longer open as a tab
/// is left alone: the window is raised and nothing else changes.
final notificationClickRouterProvider =
    Provider<StreamSubscription<NotificationTarget>>((ref) {
      final sub = ref.watch(desktopNotifierProvider).clicks.listen((t) async {
        try {
          await ref.read(windowRaiseProvider)();
          final tabs = ref.read(workspaceProvider).tabs;
          final tab = tabs.where((x) => x.path == t.repoPath).firstOrNull;
          if (tab == null) return;
          ref.read(workspaceProvider.notifier).setActive(tab.id);
          final kind = t.kind;
          final number = t.prNumber;
          final target = t.targetBranch;
          if (kind == null || number == null || target == null) return;
          await openPullRequestReview(
            ref,
            repoPath: tab.path,
            kind: kind,
            number: number,
            targetBranch: target,
          );
        } catch (_) {
          // A click must never take the app down; the window is up already.
        }
      });
      ref.onDispose(sub.cancel);
      return sub;
    });
