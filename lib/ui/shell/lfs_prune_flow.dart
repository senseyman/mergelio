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
  final (:completed, :preview) = await actions.lfsPrunePreview();
  if (!completed) return; // the failure, skip or cancel was already shown
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
