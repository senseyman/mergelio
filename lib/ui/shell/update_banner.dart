import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/update/update_manifest.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/settings_controller.dart';
import '../../state/update_controller.dart';

/// A strip above the status bar rather than a dialog: an update never covers
/// the work in progress and never steals focus.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateStatusProvider);
    final l = AppLocalizations.of(context);
    final busy = ref.watch(busyProvider) != null;
    final controller = ref.read(updateStatusProvider.notifier);

    return switch (status) {
      // A failed background check is not worth interrupting anyone over. A
      // check made from Preferences reports its own errors.
      UpdateIdle() ||
      UpdateChecking() ||
      UpdateNone() ||
      UpdateFailed() => const SizedBox.shrink(),
      UpdateFound(:final available) => _Strip(
        text: l.updateBannerAvailable('${available.version}'),
        actions: [
          if (available.canInstall && controller.canInstallInPlace)
            _Action(l.updateActionDownload, controller.download)
          else
            _Action(l.updateActionNotes, () => openNotes(available.manifest)),
          _Action(l.updateActionSkip, controller.skip),
          _Action(l.updateActionLater, controller.dismiss),
        ],
      ),
      UpdateDownloading(:final progress) => _Strip(
        text: l.updateBannerDownloading,
        progress: progress,
      ),
      UpdateReady() => _Strip(
        text: busy ? l.updateBlockedBusy : l.updateBannerReady,
        actions: [
          if (!busy) _Action(l.updateActionInstall, controller.install),
          _Action(l.updateActionLater, controller.dismiss),
        ],
      ),
    };
  }
}

/// One line of text, optional progress, then the actions on the right.
class _Strip extends StatelessWidget {
  final String text;
  final double? progress;
  final List<_Action> actions;

  const _Strip({required this.text, this.progress, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: t.bgElevated,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: t.textPrimary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (progress != null)
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(value: progress),
            ),
          for (final action in actions)
            TextButton(onPressed: action.onTap, child: Text(action.label)),
        ],
      ),
    );
  }
}

class _Action {
  final String label;
  final VoidCallback onTap;
  const _Action(this.label, this.onTap);
}

/// Opens the release page in the user's browser, the same way reveal.dart hands
/// a path to the desktop environment.
Future<void> openNotes(UpdateManifest manifest) async {
  final (exe, args) = switch (Platform.operatingSystem) {
    'macos' => ('open', [manifest.notesUrl]),
    'windows' => ('explorer', [manifest.notesUrl]),
    _ => ('xdg-open', [manifest.notesUrl]),
  };
  await Process.run(exe, args);
}

/// The one-time question, put on first launch and never again. Either answer is
/// recorded, so neither leaves the app asking twice.
Future<void> showUpdateConsentDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = AppLocalizations.of(context);
  final agreed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.updateConsentTitle),
      content: Text(l.updateConsentBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.updateConsentNo),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.updateConsentYes),
        ),
      ],
    ),
  );

  final on = agreed ?? false;
  ref.read(settingsProvider.notifier).setUpdateConsent(on ? 'on' : 'off');
  if (on) await ref.read(updateStatusProvider.notifier).check(manual: true);
}
