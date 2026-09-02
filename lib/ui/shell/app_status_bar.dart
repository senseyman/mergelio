import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/feedback.dart';
import '../../state/profiles.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../profiles/profiles_dialog.dart';
import '../../l10n/gen/app_localizations.dart';

/// Bottom status strip. Left: active profile, repo, branch + live
/// ahead/behind. Right: theme toggle and the current zoom level.
class AppStatusBar extends ConsumerWidget {
  const AppStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final tab = ref.watch(workspaceProvider).activeTab;
    final branches = tab == null
        ? const <Branch>[]
        : (ref.watch(repoDataProvider(tab.path)).valueOrNull?.branches ??
              const <Branch>[]);
    Branch? current;
    for (final b in branches) {
      if (b.current) {
        current = b;
        break;
      }
    }

    final profile = ref.watch(profilesProvider).active;
    final settings = ref.watch(settingsProvider);
    final dark = switch (settings.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: t.textMuted, fontSize: 11),
        child: Row(
          children: [
            // Profile leads the left cluster.
            InkWell(
              onTap: () => showProfilesDialog(context),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: profile == null
                          ? t.textFaint
                          : Color(profile.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(profile?.label ?? l.sbarNoProfile),
                ],
              ),
            ),
            _dot(t),
            Text(tab?.name ?? l.sbarNoRepository),
            if (tab != null) ...[
              _dot(t),
              Icon(Icons.call_split, size: 12, color: t.textMuted),
              const SizedBox(width: 4),
              Text(current?.name ?? 'detached'),
              if (current != null) ...[
                _dot(t),
                Text('↑${current.ahead} ↓${current.behind}'),
              ],
            ],
            const Spacer(),
            const _RunningOp(),
            // Theme toggle + zoom close the right cluster.
            InkWell(
              onTap: () => ref.read(settingsProvider.notifier).toggleTheme(),
              child: Row(
                children: [
                  Icon(
                    dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    size: 12,
                    color: t.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(dark ? l.sbarDark : l.sbarLight),
                ],
              ),
            ),
            _dot(t),
            Text('${(settings.uiScale * 100).round()}%'),
          ],
        ),
      ),
    );
  }

  Widget _dot(AppTokens t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text('·', style: TextStyle(color: t.textFaint)),
  );
}

/// Names whatever git operation is running and offers to abandon it. A fetch
/// or push against a remote that has stopped answering would otherwise sit
/// there for minutes with nothing to click.
class _RunningOp extends ConsumerWidget {
  const _RunningOp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    // The repository lane first: it is the one holding other actions back.
    final busy = ref.watch(busyProvider) ?? ref.watch(fetchBusyProvider);
    if (busy == null) return const SizedBox.shrink();

    return Row(
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: t.accent),
        ),
        const SizedBox(width: 6),
        Text(busy.label, key: runningOpLabelKey),
        if (busy.onCancel != null)
          Tooltip(
            message: l.sbarCancelBusy(busy.label),
            child: IconButton(
              key: cancelRunningOpKey,
              iconSize: 12,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.close),
              color: t.textMuted,
              onPressed: busy.onCancel,
            ),
          ),
        _gap(t),
      ],
    );
  }

  Widget _gap(AppTokens t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text('·', style: TextStyle(color: t.textFaint)),
  );
}

/// Names the running operation in the status bar.
const runningOpLabelKey = Key('status-running-op');

/// Abandons the running operation.
const cancelRunningOpKey = Key('status-cancel-op');
