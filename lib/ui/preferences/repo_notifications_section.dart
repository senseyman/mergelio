import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/forge_refresh.dart';
import '../../state/notification_prefs.dart';
import '../../state/settings_controller.dart';

/// One repository's say on each kind of notification: follow the global
/// default, or force it on or off. Stays editable while the master switch is
/// off, so a repository can be set up before notifications are turned on.
class RepoNotificationsSection extends ConsumerWidget {
  final String repoPath;
  const RepoNotificationsSection({super.key, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final prefs = ref.watch(repoNotifyPrefsProvider(repoPath));
    final ctl = ref.read(repoNotifyPrefsProvider(repoPath).notifier);
    // Only a definite "no account" warns; while it is still being worked out
    // (or could not be) there is nothing to say.
    final noForge =
        ref.watch(forgeRefreshEligibleProvider(repoPath)).valueOrNull == false;

    String onOff(bool v) => v ? l.ntfOn : l.ntfOff;

    Widget row(NotifyEvent e, String label, bool global) {
      final warn = noForge && e != NotifyEvent.longOps;
      return Padding(
        key: ValueKey('ntf-repo-row-${e.name}'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<NotifyOverride>(
                  key: ValueKey('ntf-repo-${e.name}'),
                  value: prefs.of(e),
                  isDense: true,
                  dropdownColor: t.bgElevated,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  items: [
                    DropdownMenuItem(
                      value: NotifyOverride.inherit,
                      child: Text(l.ntfUseGlobal(onOff(global))),
                    ),
                    DropdownMenuItem(
                      value: NotifyOverride.on,
                      child: Text(l.ntfOn),
                    ),
                    DropdownMenuItem(
                      value: NotifyOverride.off,
                      child: Text(l.ntfOff),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) ctl.set(e, v);
                  },
                ),
              ],
            ),
            if (warn)
              Text(
                l.ntfNoForge,
                style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.ntfRepoSection,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!s.notificationsEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.ntfRepoMasterOff,
                style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
              ),
            ),
          const SizedBox(height: 4),
          row(NotifyEvent.longOps, l.ntfEventLongOps, s.notifyLongOps),
          row(NotifyEvent.ci, l.ntfEventCi, s.notifyCi),
          row(
            NotifyEvent.pullRequests,
            l.ntfEventPullRequests,
            s.notifyPullRequests,
          ),
        ],
      ),
    );
  }
}
