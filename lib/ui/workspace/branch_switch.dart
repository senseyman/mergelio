import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/git/models.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../common/confirm.dart';

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
  final actions = ref.read(repoActionsProvider(repoPath));
  if (localBranch != null) {
    await actions.checkout(localBranch);
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
    await actions.checkout(rb.branch);
    return;
  }
  if (!context.mounted) return;
  final ok = await confirmDestructive(
    ref,
    context,
    title: 'Reset ${rb.branch} to ${rb.name}?',
    body:
        'This moves local ${rb.branch} to ${rb.name}, discarding any commits '
        'not on the remote. Uncommitted changes are stashed (undoable).',
    confirmLabel: 'Reset & switch',
  );
  if (!ok) return;
  await actions.switchResettingToRemote(rb);
}
