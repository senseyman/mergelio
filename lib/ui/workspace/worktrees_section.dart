import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/worktree.dart';
import '../../domain/path_key.dart';
import '../../domain/reveal.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../../state/worktrees.dart';
import '../common/dialogs.dart';
import 'sidebar_section.dart';
import 'worktree_dialogs.dart';
import '../../l10n/gen/app_localizations.dart';

/// Sidebar section listing every worktree of the active repository, so a
/// branch checked out elsewhere — or a worktree that is locked, prunable, or
/// bare — is visible without leaving the graph.
class WorktreesSection extends ConsumerWidget {
  final String repoPath;
  const WorktreesSection({super.key, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final trees =
        ref.watch(worktreesProvider(repoPath)).valueOrNull ??
        const <Worktree>[];
    final collapsed = ref.watch(
      settingsProvider.select((s) => s.collapsedSections),
    );
    final ctl = ref.read(settingsProvider.notifier);
    final activePath = ref.watch(workspaceProvider).activeTab?.path;

    return SidebarSection(
      id: 'worktrees',
      // Not call_split: that is the Branches section's icon, and two sections
      // wearing one glyph read as the same thing. This is the glyph the branch
      // badge and the tab marker already use to mean "worktree".
      icon: Icons.dashboard_outlined,
      label: l.wtsWorktrees,
      count: trees.length,
      emptyLabel: l.wtsNoWorktrees,
      open: !(collapsed['worktrees'] ?? false),
      onToggle: () => ctl.toggleSection('worktrees'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, size: 14, color: t.textFaint),
            padding: EdgeInsets.zero,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'prune',
                height: 34,
                child: Text(l.wtsPruneMenu),
              ),
            ],
            onSelected: (_) async {
              final actions = ref.read(repoActionsProvider(repoPath));
              final report = await actions.worktreePrune(dryRun: true);
              if (!context.mounted) return;
              if (await showPruneDialog(context, report)) {
                await actions.worktreePrune();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 14),
            tooltip: l.wtAdd,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () async {
              final data = await showAddWorktreeDialog(
                context,
                repoPath: repoPath,
                existing: trees,
                branches: [
                  for (final b
                      in ref
                              .read(repoDataProvider(repoPath))
                              .valueOrNull
                              ?.branches ??
                          const [])
                    b.name,
                ],
                currentBranch: ref
                    .read(repoDataProvider(repoPath))
                    .valueOrNull
                    ?.branches
                    .where((b) => b.current)
                    .firstOrNull
                    ?.name,
                hasSubmodules:
                    ref
                        .read(repoDataProvider(repoPath))
                        .valueOrNull
                        ?.submodules
                        .isNotEmpty ??
                    false,
              );
              if (data == null) return;
              final ok = await ref
                  .read(repoActionsProvider(repoPath))
                  .worktreeAdd(
                    data.path,
                    newBranch: data.newBranch,
                    startPoint: data.startPoint,
                    existingBranch: data.existingBranch,
                    detach: data.detach,
                  );
              if (ok && data.openTab) {
                ref.read(workspaceProvider.notifier).openRepo(data.path);
              }
            },
          ),
        ],
      ),
      children: [
        for (final w in trees) _row(context, ref, w, activePath, trees),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Worktree w,
    String? activePath,
    List<Worktree> siblings,
  ) {
    final l = AppLocalizations.of(context);
    final isActive = activePath != null && samePath(activePath, w.path);
    final openable = !isActive && w.kind != WorktreeKind.bare && !w.prunable;
    return _WorktreeRow(
      worktree: w,
      isActive: isActive,
      onOpen: openable
          ? () => ref.read(workspaceProvider.notifier).openRepo(w.path)
          : null,
      onMenu: (choice) async {
        final actions = ref.read(repoActionsProvider(repoPath));
        switch (choice) {
          case 'open':
            ref.read(workspaceProvider.notifier).openRepo(w.path);
          case 'reveal':
            await revealInFileManager(w.path);
          case 'move':
            final to = await showMoveWorktreeDialog(
              context,
              w,
              repoPath: repoPath,
              existing: siblings,
            );
            // null is a cancel, and a destination that only differs in
            // spelling from where the worktree already sits is not a move.
            if (to == null) return;
            if (!context.mounted) return;
            if (!samePath(to, w.path)) {
              await actions.worktreeMove(w.path, to);
            }
          case 'lock':
            // The reason really is optional, so the dialog accepts an empty
            // field and returns '' for it. Null means the user cancelled and
            // must therefore lock nothing — without this check, Cancel was the
            // only way to reach a reasonless lock.
            final reason = await showInputDialog(
              context,
              title: l.wtsLockTitle(w.name),
              label: l.wtsReasonOptional,
              confirmLabel: l.wtsLock,
              allowEmpty: true,
            );
            if (reason == null) return;
            if (!context.mounted) return;
            await actions.worktreeLock(
              w.path,
              reason: reason.isEmpty ? null : reason,
            );
          case 'unlock':
            await actions.worktreeUnlock(w.path);
          case 'remove':
            if (!await showRemoveWorktreeDialog(context, w)) return;
            if (!context.mounted) return;
            final err = await actions.worktreeRemove(w.path);
            if (err == null) return;
            if (!context.mounted) return;
            if (await showForceRemoveDialog(context, w, err)) {
              await actions.worktreeRemove(w.path, force: true);
            }
        }
      },
    );
  }
}

/// One worktree row: branch name (or short head when detached) over the
/// directory it lives in, plus a `(this)` marker, lock icon, or warning icon
/// as the state requires.
///
/// The path is not decoration. Two worktrees on `feat/login` and
/// `feat/login-2` are otherwise a single character apart, and the whole point
/// of the list is knowing which directory each branch is in.
class _WorktreeRow extends StatelessWidget {
  final Worktree worktree;
  final bool isActive;
  final VoidCallback? onOpen;
  final ValueChanged<String> onMenu;
  const _WorktreeRow({
    required this.worktree,
    required this.isActive,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final label = worktree.detached
        ? worktree.shortHead
        : (worktree.branch ?? worktree.name);
    return InkWell(
      hoverColor: t.hover,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 5, 10, 5),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                // The ellipsized path below can hide the part that
                // distinguishes two worktrees; the tooltip always has all
                // of it.
                message: worktree.path,
                waitDuration: const Duration(milliseconds: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive ? t.textPrimary : t.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      worktree.path,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textFaint, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '(this)',
                  style: TextStyle(color: t.textFaint, fontSize: 11),
                ),
              ),
            if (worktree.locked)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: worktree.lockReason ?? l.wtsLocked,
                  child: Icon(Icons.lock_outline, size: 13, color: t.textFaint),
                ),
              ),
            if (worktree.prunable)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: worktree.prunableReason ?? l.wtsPrunable,
                  child: Icon(
                    Icons.warning_amber_outlined,
                    size: 13,
                    color: t.warning,
                  ),
                ),
              ),
            PopupMenuButton<String>(
              tooltip: '',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_horiz, size: 14, color: t.textFaint),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'open',
                  height: 34,
                  enabled: onOpen != null && !isActive,
                  child: Text(l.wtsOpenInTab),
                ),
                PopupMenuItem(
                  value: 'reveal',
                  height: 34,
                  child: Text(l.wtsRevealInFinder),
                ),
                PopupMenuItem(
                  value: 'move',
                  height: 34,
                  // Git refuses to move the main worktree.
                  enabled: worktree.kind == WorktreeKind.linked,
                  child: Text(l.wtsMoveMenu),
                ),
                PopupMenuItem(
                  value: worktree.locked ? 'unlock' : 'lock',
                  height: 34,
                  child: Text(worktree.locked ? l.wtsUnlock : l.wtsLockMenu),
                ),
                PopupMenuItem(
                  value: 'remove',
                  height: 34,
                  // The main worktree cannot be removed, and a locked one
                  // must be unlocked first.
                  enabled:
                      worktree.kind == WorktreeKind.linked && !worktree.locked,
                  child: Text(l.wtsRemoveMenu),
                ),
              ],
              onSelected: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}
