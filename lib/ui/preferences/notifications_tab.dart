import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/notification_prefs.dart';
import '../../state/settings.dart';
import '../../state/settings_controller.dart';
import 'prefs_rows.dart';

/// Preferences → Notifications: the master switch, the global default for
/// each kind of event and the long-operation threshold. A repository can
/// override the per-event defaults from the Repository tab.
class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    final master = s.notificationsEnabled;

    Widget event(NotifyEvent e, String label, bool value) => KeyedSubtree(
      key: ValueKey('ntf-${e.name}'),
      child: SwitchRow(label, value, master ? (v) => c.setNotify(e, v) : null),
    );

    // A stored value that is not on offer is listed too, so the dropdown
    // never points at an item it does not have.
    final choices = {...kNotifyLongOpChoices, s.notifyLongOpSeconds}.toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        KeyedSubtree(
          key: const ValueKey('ntf-master'),
          child: SwitchRow(l.ntfMaster, master, c.setNotificationsEnabled),
        ),
        const SizedBox(height: 4),
        event(NotifyEvent.longOps, l.ntfEventLongOps, s.notifyLongOps),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.ntfLongOpThreshold,
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                key: const ValueKey('ntf-secs'),
                value: s.notifyLongOpSeconds,
                isDense: true,
                dropdownColor: t.bgElevated,
                style: TextStyle(color: t.textPrimary, fontSize: 13),
                items: [
                  for (final n in choices)
                    DropdownMenuItem(
                      value: n,
                      child: Text(l.ntfLongOpSeconds(n)),
                    ),
                ],
                onChanged: master && s.notifyLongOps
                    ? (v) {
                        if (v != null) c.setNotifyLongOpSeconds(v);
                      }
                    : null,
              ),
            ],
          ),
        ),
        event(NotifyEvent.ci, l.ntfEventCi, s.notifyCi),
        event(
          NotifyEvent.pullRequests,
          l.ntfEventPullRequests,
          s.notifyPullRequests,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text(
            l.ntfForgeHelp,
            style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }
}
