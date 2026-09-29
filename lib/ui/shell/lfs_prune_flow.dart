import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/repo_actions.dart';
import '../common/dialogs.dart';

/// Prune never deletes blind: it previews what would go, says so, and only
/// removes anything after the user confirms.
Future<void> showLfsPruneFlow(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) async {
  final l = AppLocalizations.of(context);
  final actions = ref.read(repoActionsProvider(repoPath));
  final toasts = ref.read(toastProvider.notifier);
  // A busy lane makes the preview skip with a warning and no result; that is
  // not an unreadable report, so it must not be reported as one.
  final wasBusy = ref.read(busyProvider) != null;
  final (:ran, :preview) = await actions.lfsPrunePreview();
  if (!ran || wasBusy) return; // the failure or skip was already shown
  if (preview == null) {
    toasts.show(l.lfsPruneUnreadable, kind: ToastKind.error);
    return;
  }
  if (preview.count == 0) {
    toasts.show(l.lfsPruneNothing, kind: ToastKind.info);
    return;
  }
  if (!context.mounted) return;
  final ok = await showConfirmDialog(
    context,
    title: l.lfsPruneTitle,
    body: l.lfsPruneBody(preview.count),
    confirmLabel: l.lfsPruneConfirm,
  );
  if (ok) await actions.lfsPrune();
}
