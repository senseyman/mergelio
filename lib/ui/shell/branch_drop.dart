import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/git/models.dart';
import '../../domain/git/remote_ref.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import 'remote_merge_confirm.dart';

/// What a branch dropped onto a branch or commit can do.
enum BranchDrop {
  merge,
  rebase,
  fastForward,
  moveHere,
  resetSoft,
  resetMixed,
  resetHard,
  cherryPick,
  createBranch;

  /// Options that can lose commits or uncommitted work, confirmed through the
  /// destructive-action preference and styled as dangerous.
  bool get destructive => this == resetHard || this == moveHere;
}

/// Where a branch was dropped: onto a local branch, a remote-tracking branch,
/// or a bare commit.
class BranchDropTarget {
  /// Branch name, remote-tracking ref (`origin/main`) or commit sha.
  final String ref;
  final bool isBranch;

  /// Set for a remote-tracking target, which cannot be moved or reset; a merge
  /// into it lands on its local branch instead.
  final RemoteBranch? remote;

  const BranchDropTarget.branch(String name)
    : ref = name,
      isBranch = true,
      remote = null;
  const BranchDropTarget.commit(String sha)
    : ref = sha,
      isBranch = false,
      remote = null;
  BranchDropTarget.remote(RemoteBranch rb)
    : ref = rb.name,
      isBranch = true,
      remote = rb;

  /// What the menu calls this target: the branch name, or a short sha.
  String get label => isBranch || ref.length <= 7 ? ref : ref.substring(0, 7);

  /// The branch a merge lands on: a remote target's local counterpart.
  String get mergeLabel => remote?.branch ?? label;
}

/// What is under the pointer when a dragged branch is let go: a branch label,
/// or a commit (anywhere on a graph row that is not a label).
class DropSpot {
  /// The label's text, or the commit's sha.
  final String ref;
  final bool isLabel;

  /// The commit is a stash's, drawn in the graph but not part of history.
  final bool isStash;

  const DropSpot.label(String name)
    : ref = name,
      isLabel = true,
      isStash = false;
  const DropSpot.commit(String sha, {this.isStash = false})
    : ref = sha,
      isLabel = false;
}

/// The one rule for what dropping branch [source] on [spot] means, or null
/// when the drop is refused.
///
/// A label is a drop on the branch it names, local or remote-tracking; a label
/// naming no branch (the HEAD marker) is refused. A commit is a drop on that
/// commit, whether or not a branch sits on it — aiming at a branch means
/// aiming at its label. Refused too: a stash commit, the source itself, and
/// the source's own tip, where every option would be a no-op.
BranchDropTarget? resolveBranchDrop({
  required String source,
  required DropSpot spot,
  required List<Branch> branches,
  required List<RemoteBranch> remoteBranches,
}) {
  if (spot.isStash || spot.ref == source) return null;
  final sourceTip =
      branches.where((b) => b.name == source).firstOrNull?.tip ??
      remoteBranches.where((rb) => rb.name == source).firstOrNull?.tip;
  bool isSourceTip(String sha) =>
      sourceTip != null && sourceTip.isNotEmpty && sourceTip == sha;
  if (!spot.isLabel) {
    return isSourceTip(spot.ref) ? null : BranchDropTarget.commit(spot.ref);
  }
  for (final rb in remoteBranches) {
    if (rb.name == spot.ref) {
      return isSourceTip(rb.tip) ? null : BranchDropTarget.remote(rb);
    }
  }
  for (final b in branches) {
    if (b.name == spot.ref) {
      return isSourceTip(b.tip) ? null : BranchDropTarget.branch(b.name);
    }
  }
  return null;
}

/// Menu options for dropping a branch on [target], in menu order.
///
/// A remote-tracking source cannot be moved or reset, so it only merges or
/// rebases, and so does any branch dropped on one. The current branch is reset in one of git's three modes; any
/// other branch is simply moved, which needs no checkout. [canFastForward]
/// says the target branch is behind the source.
List<BranchDrop> branchDropOptions({
  required bool sourceIsRemote,
  required bool sourceIsCurrent,
  required BranchDropTarget target,
  required bool canFastForward,
}) {
  if (target.remote != null) {
    return const [BranchDrop.merge, BranchDrop.rebase];
  }
  final resets = sourceIsCurrent
      ? const [
          BranchDrop.resetSoft,
          BranchDrop.resetMixed,
          BranchDrop.resetHard,
        ]
      : const [BranchDrop.moveHere];
  if (target.isBranch) {
    return [
      BranchDrop.merge,
      BranchDrop.rebase,
      if (!sourceIsRemote) ...[
        if (canFastForward) BranchDrop.fastForward,
        ...resets,
      ],
    ];
  }
  return [
    BranchDrop.rebase,
    if (!sourceIsRemote) ...[
      ...resets,
      BranchDrop.cherryPick,
      BranchDrop.createBranch,
    ],
  ];
}

/// Opens the menu for [source] dropped on [target] at [at], confirms the
/// chosen option and runs it.
Future<void> showBranchDropMenu(
  BuildContext context,
  WidgetRef ref, {
  required String repoPath,
  required String source,
  required BranchDropTarget target,
  required Offset at,
}) async {
  final actions = ref.read(repoActionsProvider(repoPath));
  final RepoData data;
  try {
    data = await ref.read(repoDataProvider(repoPath).future);
  } on Object catch (_) {
    return;
  }
  final sourceIsRemote = splitRemoteRef(source, data.remotes) != null;
  final options = branchDropOptions(
    sourceIsRemote: sourceIsRemote,
    sourceIsCurrent: data.branches.any((b) => b.current && b.name == source),
    target: target,
    canFastForward:
        target.isBranch &&
        !sourceIsRemote &&
        await actions.isAncestor(target.ref, source),
  );
  if (!context.mounted) return;
  final l = AppLocalizations.of(context);
  final chosen = await showContextMenu<BranchDrop>(
    context: context,
    position: at,
    items: [
      for (final o in options)
        PopupMenuItem(
          height: 34,
          value: o,
          child: Text(
            branchDropLabel(l, o, source, target),
            style: const TextStyle(fontSize: 13),
          ),
        ),
    ],
  );
  if (chosen == null || !context.mounted) return;
  await _run(context, ref, actions, repoPath, chosen, source, target);
}

/// Menu text for option [o], also used as the confirm dialog's title.
String branchDropLabel(
  AppLocalizations l,
  BranchDrop o,
  String source,
  BranchDropTarget to,
) {
  final target = to.label;
  return switch (o) {
    BranchDrop.merge => l.sbMergeSourceInto(source, to.mergeLabel),
    BranchDrop.rebase => l.sbRebaseSourceOnto(source, target),
    BranchDrop.fastForward => l.bdFastForward(source, target),
    BranchDrop.moveHere => l.bdMoveHere(source, target),
    BranchDrop.resetSoft => l.bdResetSoft(source, target),
    BranchDrop.resetMixed => l.bdResetMixed(source, target),
    BranchDrop.resetHard => l.bdResetHard(source, target),
    BranchDrop.cherryPick => l.bdCherryPick(source, target),
    BranchDrop.createBranch => l.menuCreateBranch,
  };
}

String _body(
  AppLocalizations l,
  BranchDrop o,
  String source,
  BranchDropTarget to,
) {
  final target = to.label;
  return switch (o) {
    BranchDrop.merge => l.bdMergeBody(source, to.mergeLabel),
    BranchDrop.rebase => l.bdRebaseBody(source, target),
    BranchDrop.fastForward => l.bdFastForwardBody(source, target),
    BranchDrop.moveHere => l.bdMoveHereBody(source, target),
    BranchDrop.resetSoft => l.bdResetSoftBody(source, target),
    BranchDrop.resetMixed => l.bdResetMixedBody(source, target),
    BranchDrop.resetHard => l.bdResetHardBody(source, target),
    BranchDrop.cherryPick => l.bdCherryPickBody(source, target),
    BranchDrop.createBranch => '',
  };
}

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  RepoActions actions,
  String repoPath,
  BranchDrop o,
  String source,
  BranchDropTarget target,
) async {
  final l = AppLocalizations.of(context);
  // Naming the branch is its own confirmation.
  if (o == BranchDrop.createBranch) {
    final name = await showInputDialog(
      context,
      title: l.ropCreateBranchTitle,
      label: l.ropBranchName,
    );
    if (name != null) await actions.createBranch(name, at: target.ref);
    return;
  }
  final title = branchDropLabel(l, o, source, target);
  final body = _body(l, o, source, target);
  final ok = o.destructive
      ? await confirmDestructive(ref, context, title: title, body: body)
      : await showConfirmDialog(
          context,
          title: title,
          body: body,
          danger: false,
        );
  if (!ok || !context.mounted) return;
  switch (o) {
    case BranchDrop.merge:
      if (await confirmRemoteSource(
        context,
        ref,
        repoPath: repoPath,
        source: source,
      )) {
        final rb = target.remote;
        await (rb != null
            ? actions.mergeIntoRemote(source, rb)
            : actions.mergeInto(source, target.ref));
      }
    case BranchDrop.rebase:
      await actions.rebaseOnto(source, target.ref);
    case BranchDrop.fastForward:
      await actions.fastForward(target.ref, source);
    case BranchDrop.moveHere:
      await actions.moveBranch(source, target.ref);
    case BranchDrop.resetSoft:
      await actions.resetSoft(target.ref);
    case BranchDrop.resetMixed:
      await actions.resetMixed(target.ref);
    case BranchDrop.resetHard:
      await actions.resetHard(target.ref);
    case BranchDrop.cherryPick:
      await actions.cherryPickOnto(source, target.ref);
    case BranchDrop.createBranch:
      break;
  }
}
