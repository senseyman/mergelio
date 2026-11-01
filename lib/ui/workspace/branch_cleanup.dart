import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/maintenance.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/maintenance.dart';
import '../../state/repo_actions.dart';
import '../../state/settings_controller.dart';
import '../../state/worktrees.dart';
import '../common/dialogs.dart';
import '../graph/commit_columns.dart';
import 'maintenance_text.dart';

/// Opens the branch clean-up list on its own, for when tidying branches is
/// the whole errand.
Future<void> showBranchCleanup(BuildContext context, String repoPath) =>
    showAppModal<void>(
      context: context,
      title: AppLocalizations.of(context).bcTitle,
      icon: Icons.cleaning_services_outlined,
      width: 640,
      body: BranchCleanup(repoPath: repoPath),
    );

/// Local branches merged into the trunk, or stale, offered for deletion as
/// one undoable step. The trunk and current branch are never listed, and a
/// branch a worktree holds is shown but cannot be picked.
class BranchCleanup extends ConsumerStatefulWidget {
  final String repoPath;
  const BranchCleanup({super.key, required this.repoPath});

  @override
  ConsumerState<BranchCleanup> createState() => _BranchCleanupState();
}

class _BranchCleanupState extends ConsumerState<BranchCleanup> {
  final _selected = <String>{};

  Future<void> _delete(List<HygieneBranch> picked, String? trunk) async {
    final l = AppLocalizations.of(context);
    final forced = [
      for (final b in picked)
        if (b.needsForce) b.name,
    ];
    final body = [
      l.mntDeleteBody(picked.length),
      if (forced.isNotEmpty) ...[
        '',
        l.mntDeleteForce,
        for (final n in forced) '• $n',
      ],
    ].join('\n');
    final ok = await showConfirmDialog(
      context,
      title: l.mntDeleteTitle,
      body: body,
      confirmLabel: l.mntDeleteConfirm,
    );
    if (!ok || !mounted) return;
    await ref
        .read(repoActionsProvider(widget.repoPath))
        .deleteBranches(picked, trunk: trunk);
    if (!mounted) return;
    setState(_selected.clear);
    ref.invalidate(branchHygieneProvider(widget.repoPath));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final settings = ref.watch(settingsProvider);
    return ref
        .watch(branchHygieneProvider(widget.repoPath))
        .when(
          loading: mntLoading,
          error: (e, _) => mntFailed(context, e),
          data: (h) {
            // A worktree whose directory is gone still holds its branch until
            // it is pruned, which is the one thing that frees the branch.
            final vanished = {
              for (final w
                  in ref
                          .watch(worktreesProvider(widget.repoPath))
                          .valueOrNull ??
                      const [])
                if (w.prunable) w.path,
            };
            if (h.branches.isEmpty) {
              return Text(l.mntNoBranches, style: mntFaintStyle(t));
            }
            final pickable = [
              for (final b in h.branches)
                if (b.selectable) b,
            ];
            final merged = mergedPickable(h.branches);
            // A branch deleted elsewhere since it was ticked is no longer
            // on offer, and must not be deleted on the strength of that tick.
            final picked = [
              for (final b in pickable)
                if (_selected.contains(b.name)) b,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.mntMergedInto(h.trunk ?? '—', staleBranchAge.inDays),
                  style: mntFaintStyle(t),
                ),
                const SizedBox(height: 4),
                for (final b in h.branches)
                  _BranchRow(
                    branch: b,
                    holderVanished: vanished.contains(b.heldBy),
                    selected: _selected.contains(b.name),
                    date: formatCommitDate(
                      b.lastCommit,
                      format: settings.dateFormat,
                    ),
                    onChanged: b.selectable
                        ? (v) => setState(
                            () => v == true
                                ? _selected.add(b.name)
                                : _selected.remove(b.name),
                          )
                        : null,
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    TextButton(
                      onPressed: pickable.isEmpty
                          ? null
                          : () => setState(
                              () => _selected.addAll([
                                for (final b in pickable) b.name,
                              ]),
                            ),
                      child: Text(l.mntSelectAll),
                    ),
                    // Replaces the pick rather than adding to it: after
                    // Select all, it must leave the merged branches alone.
                    TextButton(
                      onPressed: merged.isEmpty
                          ? null
                          : () => setState(
                              () => _selected
                                ..clear()
                                ..addAll(merged),
                            ),
                      child: Text(l.mntSelectMerged),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: t.danger),
                      onPressed: picked.isEmpty
                          ? null
                          : () => _delete(picked, h.trunk),
                      child: Text(l.mntDeleteSelected(picked.length)),
                    ),
                  ],
                ),
              ],
            );
          },
        );
  }
}

class _BranchRow extends StatelessWidget {
  final HygieneBranch branch;

  /// The worktree holding [branch] no longer exists on disk.
  final bool holderVanished;
  final bool selected;
  final String date;
  final ValueChanged<bool?>? onChanged;

  const _BranchRow({
    required this.branch,
    this.holderVanished = false,
    required this.selected,
    required this.date,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final tags = [
      if (branch.merged) l.mntTagMerged else l.mntTagStale,
      if (branch.gone) l.mntTagGone,
      date,
      if (branch.heldBy != null)
        holderVanished
            ? l.mntHeldByPrunable(branch.heldBy!)
            : l.mntHeldBy(branch.heldBy!),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          key: ValueKey('mt-branch-${branch.name}'),
          value: selected && onChanged != null,
          onChanged: onChanged,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  branch.name,
                  style: mntBodyStyle(
                    t,
                    color: onChanged == null ? t.textMuted : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in tags) Text(s, style: mntFaintStyle(t)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
