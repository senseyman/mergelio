import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/profiles.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../brand/mergelio_mark.dart';
import '../preferences/preferences_dialog.dart';
import '../profiles/profiles_dialog.dart';
import 'global_actions.dart';
import 'shell_widgets.dart';

/// Top chrome: brand + global utilities (terminal, search, palette, settings,
/// profile). Feature buttons show placeholders until their stage lands.
class AppToolbar extends ConsumerWidget {
  const AppToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    void soon(String what) => ref
        .read(toastProvider.notifier)
        .show(what, description: 'Coming in a later stage');

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.bgApp,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          const MergelioMark(size: 24),
          const SizedBox(width: 8),
          Text(
            'Mergelio',
            style: AppFonts.disp(
              size: 15,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const Spacer(),
          BarIconButton(
            icon: Icons.terminal_outlined,
            tooltip: l.tooltipTerminal,
            onPressed: () {
              if (ref.read(workspaceProvider).activeTab == null) {
                soon('Terminal');
                return;
              }
              ref.read(settingsProvider.notifier).toggleTerminal();
            },
          ),
          BarIconButton(
            icon: Icons.search,
            tooltip: l.tooltipSearch,
            onPressed: () {
              if (ref.read(workspaceProvider).activeTab == null) {
                soon('Global search');
                return;
              }
              openGlobalSearch(ref);
            },
          ),
          BarIconButton(
            icon: Icons.keyboard_command_key,
            tooltip: l.tooltipPalette,
            onPressed: () {
              if (ref.read(workspaceProvider).activeTab == null) {
                soon('Command palette');
                return;
              }
              openGlobalPalette(context, ref);
            },
          ),
          BarIconButton(
            icon: Icons.settings_outlined,
            tooltip: l.tooltipPreferences,
            onPressed: () => showPreferencesDialog(context),
          ),
          const SizedBox(width: 4),
          Builder(
            builder: (_) {
              final active = ref.watch(profilesProvider).active;
              final initial = active != null && active.label.trim().isNotEmpty
                  ? active.label.trim()[0].toUpperCase()
                  : 'M';
              return Tooltip(
                message: l.tooltipProfiles,
                child: InkWell(
                  borderRadius: BorderRadius.circular(t.rButton),
                  onTap: () => showProfilesDialog(context),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: active != null
                          ? Color(active.colorValue)
                          : t.accent,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
