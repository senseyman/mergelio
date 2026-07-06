import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/feedback.dart';
import '../../state/settings_controller.dart';

/// Global shortcut dispatcher wrapping the app. Only the shortcuts meaningful
/// at this stage are wired; the rest arrive with their features (command
/// palette, search, undo/redo). Each binding is registered for both ⌘ (macOS)
/// and Ctrl (Windows/Linux).
class KeyboardShortcuts extends ConsumerWidget {
  final Widget child;
  const KeyboardShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void soon(String what) => ref
        .read(toastProvider.notifier)
        .show(what, description: 'Coming in a later stage');

    void toggleLeft() =>
        ref.read(settingsProvider.notifier).toggleLeftCollapsed();

    void dismissTopToast() {
      final toasts = ref.read(toastProvider);
      if (toasts.isNotEmpty) {
        ref.read(toastProvider.notifier).dismiss(toasts.last.id);
      }
    }

    Map<ShortcutActivator, VoidCallback> chord(
      LogicalKeyboardKey key,
      VoidCallback action,
    ) => {
      SingleActivator(key, meta: true): action,
      SingleActivator(key, control: true): action,
    };

    return CallbackShortcuts(
      bindings: {
        ...chord(LogicalKeyboardKey.backslash, toggleLeft),
        ...chord(LogicalKeyboardKey.keyK, () => soon('Command palette')),
        ...chord(LogicalKeyboardKey.keyF, () => soon('Global search')),
        const SingleActivator(LogicalKeyboardKey.escape): dismissTopToast,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
