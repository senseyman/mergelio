import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/logging.dart';
import '../../state/unsaved_guard.dart';

/// Holds the window open long enough to ask about unsaved editors. Quitting is
/// the one exit that cannot be undone afterwards, so the prompt happens before
/// the window goes rather than after.
///
/// Desktop only, and best-effort: if the window manager refuses to hand over
/// close handling the app quits as it always did, which is the safe direction
/// for a guard — never a window that cannot be closed.
class QuitGuard extends ConsumerStatefulWidget {
  final Widget child;
  const QuitGuard({super.key, required this.child});

  @override
  ConsumerState<QuitGuard> createState() => _QuitGuardState();
}

class _QuitGuardState extends ConsumerState<QuitGuard> with WindowListener {
  bool _listening = false;

  static bool get _desktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    if (!_desktop) return;
    windowManager.addListener(this);
    _listening = true;
    windowManager.setPreventClose(true).catchError((Object e) {
      appLog.warn('quit guard unavailable: $e', scope: 'shell');
    });
  }

  @override
  void dispose() {
    if (_listening) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    var go = true;
    try {
      go = await ref.read(unsavedGuardsProvider).confirmAll();
    } on Object catch (e) {
      // A guard that blew up must not trap the user in the app.
      appLog.warn('unsaved check failed on quit: $e', scope: 'shell');
    }
    if (!go) return;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
