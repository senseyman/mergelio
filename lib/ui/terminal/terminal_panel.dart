import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/tokens.dart';
import '../../state/settings_controller.dart';
import '../../state/terminal.dart';
import '../../state/workspace.dart';
import '../../l10n/gen/app_localizations.dart';

/// The dockable terminal: a header with the repo path + close button, and an
/// xterm view bound to the active repo's PTY session. Shown only when a repo is
/// open and the persisted terminalOpen setting is on; toggled by ⌘`.
class TerminalPanel extends ConsumerWidget {
  const TerminalPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final tab = ref.watch(workspaceProvider.select((w) => w.activeTab));
    if (tab == null) return const SizedBox.shrink();
    final session = ref.watch(terminalSessionProvider(tab.path));
    final height = ref.watch(settingsProvider.select((s) => s.terminalHeight));
    final ctl = ref.read(settingsProvider.notifier);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        children: [
          // Drag strip along the top edge resizes the dock (persisted).
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) =>
                  ctl.setTerminalHeight(height - d.delta.dy),
              child: const SizedBox(height: 6, width: double.infinity),
            ),
          ),
          Container(
            height: 30,
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 14, color: t.textFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tab.path,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textFaint,
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.termClose,
                  icon: const Icon(Icons.close, size: 15),
                  color: t.textMuted,
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .setTerminalOpen(false),
                ),
              ],
            ),
          ),
          Expanded(
            child: TerminalView(
              session.terminal,
              padding: const EdgeInsets.all(8),
              theme: _terminalTheme(t),
              textStyle: const TerminalStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  TerminalTheme _terminalTheme(AppTokens t) => TerminalTheme(
    cursor: t.accent,
    selection: t.accent.withValues(alpha: 0.3),
    foreground: t.textPrimary,
    background: t.bgPanel,
    black: const Color(0xFF2E2E2E),
    red: const Color(0xFFD92D20),
    green: const Color(0xFF0E9F6E),
    yellow: const Color(0xFFB54708),
    blue: const Color(0xFF4C5BF5),
    magenta: const Color(0xFF7A5AF8),
    cyan: const Color(0xFF0BA5EC),
    white: const Color(0xFFE6E6E6),
    brightBlack: const Color(0xFF6B6B6B),
    brightRed: const Color(0xFFF04438),
    brightGreen: const Color(0xFF12B76A),
    brightYellow: const Color(0xFFDC6803),
    brightBlue: const Color(0xFF6E7BFF),
    brightMagenta: const Color(0xFF9B8AFB),
    brightCyan: const Color(0xFF36BFFA),
    brightWhite: const Color(0xFFFFFFFF),
    searchHitBackground: t.accent,
    searchHitBackgroundCurrent: t.accent,
    searchHitForeground: t.textPrimary,
  );
}
