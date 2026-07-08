import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/search.dart';
import '../../state/feedback.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/search.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../palette/command_palette.dart';

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

    void openSearch() {
      if (ref.read(workspaceProvider).activeTab == null) return;
      ref.read(searchQueryProvider.notifier).state = const CommitQuery(
        text: '',
      );
    }

    void openPalette() {
      final path = ref.read(workspaceProvider).activeTab?.path;
      if (path == null) return;
      final actions = ref.read(repoActionsProvider(path));
      final data = ref.read(repoDataProvider(path)).valueOrNull;
      final cmds = <PaletteCommand>[
        PaletteCommand('Fetch', Icons.download_outlined, () => actions.fetch()),
        PaletteCommand('Pull', Icons.south_west, () => actions.pull()),
        PaletteCommand('Push', Icons.north_east, () => actions.push()),
        PaletteCommand('Global search', Icons.search, () async => openSearch()),
        for (final b in data?.branches ?? const [])
          PaletteCommand(
            'Checkout: ${b.name}',
            Icons.call_split,
            () => actions.checkout(b.name),
          ),
        for (final c in (data?.commits ?? const []).take(200))
          PaletteCommand(
            'Fly to: ${c.shortSha}  ${c.message}',
            Icons.my_location,
            () async => ref.read(selectedCommitProvider.notifier).state = c.sha,
          ),
      ];
      showCommandPalette(context, commands: cmds);
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
        ...chord(LogicalKeyboardKey.keyF, openSearch),
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
