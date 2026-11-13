import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_actions.dart';
import '../common/confirm.dart';

/// Starts splitting [sha], asking first when the commit is already on a
/// remote: rewriting it there means a force push.
Future<void> splitCommit(
  BuildContext context,
  WidgetRef ref, {
  required String repoPath,
  required String sha,
}) async {
  final l = AppLocalizations.of(context);
  // Read before the dialog: `ref` belongs to a widget the modal outlives.
  final actions = ref.read(repoActionsProvider(repoPath));
  final remotes = await actions.remoteBranchesContaining(sha);
  if (remotes.isNotEmpty) {
    if (!context.mounted) return;
    final ok = await confirmDestructive(
      ref,
      context,
      title: l.rewordPushedTitle,
      body: l.splitPushedBody(remotes.join(', ')),
      confirmLabel: l.rewordPushedConfirm,
    );
    if (!ok) return;
  }
  await actions.splitCommit(sha);
}
