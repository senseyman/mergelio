import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/feedback.dart';
import '../../state/repo_actions.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../preferences/preferences_dialog.dart';
import 'global_actions.dart';
import 'repo_op_dialogs.dart';

/// Global shortcut dispatcher wrapping the app. Only the shortcuts meaningful
/// at this stage are wired; the rest arrive with their features (command
/// palette, search, undo/redo). Each binding is registered for both ⌘ (macOS)
/// and Ctrl (Windows/Linux).
class KeyboardShortcuts extends ConsumerWidget {
  final Widget child;
  const KeyboardShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void toggleLeft() =>
        ref.read(settingsProvider.notifier).toggleLeftCollapsed();

    RepoActions? activeActions() {
      final path = ref.read(workspaceProvider).activeTab?.path;
      return path == null ? null : ref.read(repoActionsProvider(path));
    }

    void undo() => activeActions()?.undo();
    void redo() => activeActions()?.redo();

    void toggleTerminal() {
      if (ref.read(workspaceProvider).activeTab == null) return;
      ref.read(settingsProvider.notifier).toggleTerminal();
    }

    final settings = ref.read(settingsProvider.notifier);

    void openSearch() => openGlobalSearch(ref);
    void openPalette() => openGlobalPalette(context, ref);

    void createBranch() {
      final path = ref.read(workspaceProvider).activeTab?.path;
      if (path != null) showBranchDialog(context, ref, path);
    }

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
        ...chord(LogicalKeyboardKey.keyK, openPalette),
        // ⌘⇧P — palette alias for muscle memory from other editors.
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true):
            openPalette,
        const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
          shift: true,
        ): openPalette,
        ...chord(LogicalKeyboardKey.keyF, openSearch),
        ...chord(LogicalKeyboardKey.keyB, createBranch),
        ...chord(
          LogicalKeyboardKey.comma,
          () => showPreferencesDialog(context),
        ),
        ...chord(LogicalKeyboardKey.backquote, toggleTerminal),
        // Zoom: ⌘/Ctrl with = (also + on many layouts), - and 0 to reset.
        ...chord(LogicalKeyboardKey.equal, settings.zoomIn),
        ...chord(LogicalKeyboardKey.add, settings.zoomIn),
        ...chord(LogicalKeyboardKey.minus, settings.zoomOut),
        ...chord(LogicalKeyboardKey.numpadSubtract, settings.zoomOut),
        ...chord(LogicalKeyboardKey.digit0, settings.zoomReset),
        ...chord(LogicalKeyboardKey.keyZ, undo),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): redo,
        const SingleActivator(LogicalKeyboardKey.escape): dismissTopToast,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
