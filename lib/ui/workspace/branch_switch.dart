import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/git/models.dart';
import '../../domain/path_key.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/workspace.dart';
import '../../state/worktrees.dart';
import '../common/confirm.dart';
import 'worktree_dialogs.dart';

/// Whether switching remote [rb] would reset existing local branch:
/// true only when local branch with same name exists with different tip.
bool remoteSwitchIsDestructive(RemoteBranch rb, List<Branch> locals) {
  if (!rb.hasLocal) return false;
  for (final b in locals) {
    if (b.name == rb.branch) return b.tip != rb.tip;
  }
  return false;
}

/// Resolves graph branch-chip [label] to a switch target: [RemoteBranch]
/// when label names one, otherwise local branch name.
({String? local, RemoteBranch? remote}) resolveBranchChip(
  String label,
  List<RemoteBranch> remotes,
) {
  for (final rb in remotes) {
    if ('${rb.remote}/${rb.branch}' == label) return (local: null, remote: rb);
  }
  return (local: label, remote: null);
}

/// Double-click entry point for switching to a branch. A local target is a
/// plain checkout. A remote target creates a tracking branch when no local
/// exists, checks out the local when their tips match, and otherwise (a
/// diverged local) confirms before resetting the local branch to the remote.
Future<void> activateBranch(
  WidgetRef ref,
  BuildContext context,
  String repoPath, {
  String? localBranch,
  RemoteBranch? remote,
}) async {
  final l = AppLocalizations.of(context);
  final actions = ref.read(repoActionsProvider(repoPath));

  // The local branch this call will ultimately check out, if any: the
  // explicit local target, or (for a remote target with a same-named local)
  // that local branch. A remote target with no local counterpart creates a
  // brand-new tracking branch via checkoutRemote below, which can never
  // already be checked out elsewhere, so it is deliberately left out here.
  final targetLocalBranch =
      localBranch ?? (remote != null && remote.hasLocal ? remote.branch : null);

  // Git refuses a branch already checked out elsewhere. Ask first, before
  // any destructive-reset confirmation further down, so the user gets the
  // two useful outs (or a plain cancel) rather than a git error after the
  // fact, and so cancelling here never requires first answering a question
  // about discarding commits the flow will now never reach.
  var ignoreOtherWorktrees = false;
  if (targetLocalBranch != null) {
    final holder = ref.read(
      worktreeByBranchProvider(repoPath),
    )[targetLocalBranch];
    if (holder != null && !samePath(holder.path, repoPath)) {
      final choice = await showWorktreeCollisionDialog(
        context,
        branch: targetLocalBranch,
        holder: holder,
      );
      if (!context.mounted) return;
      switch (choice) {
        case CollisionChoice.cancel:
          return;
        case CollisionChoice.openWorktree:
          ref.read(workspaceProvider.notifier).openRepo(holder.path);
          return;
        case CollisionChoice.checkoutAnyway:
          ignoreOtherWorktrees = true;
      }
    }
  }

  if (localBranch != null) {
    await actions.checkout(
      localBranch,
      ignoreOtherWorktrees: ignoreOtherWorktrees,
    );
    return;
  }
  final rb = remote!;
  if (!rb.hasLocal) {
    await actions.checkoutRemote(rb);
    return;
  }
  List<Branch> locals;
  try {
    locals = (await ref.read(repoDataProvider(repoPath).future)).branches;
  } catch (_) {
    locals = const <Branch>[];
  }
  if (!remoteSwitchIsDestructive(rb, locals)) {
    await actions.checkout(
      rb.branch,
      ignoreOtherWorktrees: ignoreOtherWorktrees,
    );
    return;
  }
  if (!context.mounted) return;
  final ok = await confirmDestructive(
    ref,
    context,
    title: l.bsResetTitle(rb.branch, rb.name),
    body: l.bsResetBody(rb.branch, rb.name),
    confirmLabel: l.bsResetAndSwitch,
  );
  if (!ok) return;
  await actions.switchResettingToRemote(
    rb,
    ignoreOtherWorktrees: ignoreOtherWorktrees,
  );
}
