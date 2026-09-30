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
  // Read through the container: the check repeats after the confirm dialog,
  // by which time the widget behind [ref] may be gone.
  final container = ProviderScope.containerOf(context, listen: false);
  // Prune runs on the repo lane, so a fetch on its own lane can overlap it
  // and prune could delete objects that fetch has just downloaded.
  bool fetchRunning() {
    if (container.read(fetchBusyProvider) == null) return false;
    toasts.show(l.bbOperationRunning, kind: ToastKind.warning);
    return true;
  }

  if (fetchRunning()) return;
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
  if (!ok || fetchRunning()) return;
  await actions.lfsPrune();
}
