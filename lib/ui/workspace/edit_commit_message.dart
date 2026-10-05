import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_actions.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import 'hooks_panel.dart';

/// Prompts for a new message for [commit] and applies it. Shared by the graph's
/// context menu and the commit details panel so both reach the same flow.
///
/// The "already pushed" warning comes after the edit rather than before it:
/// someone who opens the dialog and cancels never rewrites anything, and
/// warning them first would be a prompt about a decision they had not made yet.
Future<void> editCommitMessage(
  BuildContext context,
  WidgetRef ref, {
  required String repoPath,
  required Commit commit,
}) async {
  final l = AppLocalizations.of(context);
  // Read before the dialog: `ref` belongs to a widget the modal outlives, and
  // a background refresh can dispose it while the dialog is open.
  final actions = ref.read(repoActionsProvider(repoPath));
  // Pre-fill with the same trimming the dialog applies on the way out, so
  // "open, change nothing, save" compares equal instead of rewriting history
  // just to strip whitespace.
  final summary = commit.message.trim();
  final description = commit.body.trim();
  final edited = await showCommitMessageDialog(
    context,
    title: l.rewordTitle,
    initialSummary: summary,
    initialDescription: description,
  );
  if (edited == null) return;
  if (edited.summary == summary && edited.description == description) {
    return; // unchanged — nothing to rewrite
  }
  final remotes = await actions.remoteBranchesContaining(commit.sha);
  if (remotes.isNotEmpty) {
    if (!context.mounted) return;
    final ok = await confirmDestructive(
      ref,
      context,
      title: l.rewordPushedTitle,
      body: l.rewordPushedBody(remotes.join(', ')),
      confirmLabel: l.rewordPushedConfirm,
    );
    if (!ok) return;
  }
  final rejection = await actions.rewordCommit(
    commit.sha,
    edited.summary,
    description: edited.description,
  );
  if (rejection == null || !context.mounted) return;
  await showHookRejectedDialog(
    context,
    repoPath: repoPath,
    rejection: rejection,
    // The edit dialog has closed; retrying is how the new message survives.
    messageKept: false,
    skipLabel: l.hkRewordSkip,
    onSkip: () async {
      final again = await actions.rewordCommit(
        commit.sha,
        edited.summary,
        description: edited.description,
        noVerify: true,
      );
      // A hook --no-verify does not cover can still refuse; say so rather
      // than let the retry fail without a word.
      if (again == null || !context.mounted) return;
      await showHookRejectedDialog(
        context,
        repoPath: repoPath,
        rejection: again,
        messageKept: false,
      );
    },
  );
}
