import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../data/update/host_info.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/settings_controller.dart';
import '../../state/update_controller.dart';
import '../graph/commit_columns.dart';
import 'prefs_rows.dart';

/// Where update checking is turned on or off, and where a check the user asked
/// for reports back. The banner stays quiet about failures; this does not.
class UpdatesTab extends ConsumerWidget {
  const UpdatesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final status = ref.watch(updateStatusProvider);
    final controller = ref.read(updateStatusProvider.notifier);

    final labelStyle = TextStyle(color: t.textPrimary, fontSize: 13);
    final faintStyle = TextStyle(color: t.textFaint, fontSize: 12);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // The packaged metadata is read asynchronously, so the line appears
        // once it is known rather than showing a placeholder version.
        FutureBuilder(
          future: currentAppVersion(),
          builder: (context, snapshot) => snapshot.hasData
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l.updatePrefsCurrent('${snapshot.data}'),
                    style: labelStyle,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        SwitchRow(
          l.updatePrefsAuto,
          s.updateConsent == 'on',
          (on) => ref
              .read(settingsProvider.notifier)
              .setUpdateConsent(on ? 'on' : 'off'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            l.updatePrefsLastCheck(
              s.updateLastCheckMs == 0
                  ? l.updatePrefsNever
                  : formatCommitDate(
                      DateTime.fromMillisecondsSinceEpoch(s.updateLastCheckMs),
                      format: s.dateFormat,
                      withTime: true,
                      clock: s.clockFormat,
                    ),
            ),
            style: faintStyle,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(width: 8),
            FilledButton(
              onPressed: status is UpdateChecking
                  ? null
                  : () => controller.check(manual: true),
              child: Text(l.updatePrefsCheckNow),
            ),
            const SizedBox(width: 12),
            Expanded(child: _Result(status: status)),
          ],
        ),
        // Neither .deb nor .rpm can be replaced from inside the app without
        // desynchronising the package database, so say where the update comes
        // from instead of offering a button that cannot work.
        if (Platform.isLinux) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(l.updateLinuxHint, style: faintStyle),
          ),
        ],
      ],
    );
  }
}

class _Result extends StatelessWidget {
  final UpdateStatus status;
  const _Result({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final text = switch (status) {
      UpdateNone() => l.updateManualNone,
      UpdateFailed() => l.updateManualFailed,
      UpdateFound(:final available) => l.updateBannerAvailable(
        '${available.version}',
      ),
      UpdateReady() => l.updateBannerReady,
      UpdateDownloading() => l.updateBannerDownloading,
      UpdateIdle() || UpdateChecking() => '',
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: TextStyle(
        color: status is UpdateFailed ? t.danger : t.textPrimary,
        fontSize: 12,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
