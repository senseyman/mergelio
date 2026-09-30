import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Where a branch was dropped: onto a local branch, or onto a bare commit.
class BranchDropTarget {
  /// Branch name or commit sha.
  final String ref;
  final bool isBranch;

  const BranchDropTarget.branch(String name) : ref = name, isBranch = true;
  const BranchDropTarget.commit(String sha) : ref = sha, isBranch = false;

  /// What the menu calls this target: the branch name, or a short sha.
  String get label => isBranch || ref.length <= 7 ? ref : ref.substring(0, 7);
}

/// Menu options for dropping a branch on [target], in menu order.
///
/// A remote-tracking source cannot be moved or reset, so it only merges or
/// rebases. The current branch is reset in one of git's three modes; any
/// other branch is simply moved, which needs no checkout. [canFastForward]
/// says the target branch is behind the source.
List<BranchDrop> branchDropOptions({
  required bool sourceIsRemote,
  required bool sourceIsCurrent,
  required BranchDropTarget target,
  required bool canFastForward,
}) {
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
            branchDropLabel(l, o, source, target.label),
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
  String target,
) => switch (o) {
  BranchDrop.merge => l.sbMergeSourceInto(source, target),
  BranchDrop.rebase => l.sbRebaseSourceOnto(source, target),
  BranchDrop.fastForward => l.bdFastForward(source, target),
  BranchDrop.moveHere => l.bdMoveHere(source, target),
  BranchDrop.resetSoft => l.bdResetSoft(source, target),
  BranchDrop.resetMixed => l.bdResetMixed(source, target),
  BranchDrop.resetHard => l.bdResetHard(source, target),
  BranchDrop.cherryPick => l.bdCherryPick(source, target),
  BranchDrop.createBranch => l.menuCreateBranch,
};

String _body(AppLocalizations l, BranchDrop o, String source, String target) =>
    switch (o) {
      BranchDrop.merge => l.bdMergeBody(source, target),
      BranchDrop.rebase => l.bdRebaseBody(source, target),
      BranchDrop.fastForward => l.bdFastForwardBody(source, target),
      BranchDrop.moveHere => l.bdMoveHereBody(source, target),
      BranchDrop.resetSoft => l.bdResetSoftBody(source, target),
      BranchDrop.resetMixed => l.bdResetMixedBody(source, target),
      BranchDrop.resetHard => l.bdResetHardBody(source, target),
      BranchDrop.cherryPick => l.bdCherryPickBody(source, target),
      BranchDrop.createBranch => '',
    };

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
  final title = branchDropLabel(l, o, source, target.label);
  final body = _body(l, o, source, target.label);
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
        await actions.mergeInto(source, target.ref);
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
