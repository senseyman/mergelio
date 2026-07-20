import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import 'branch_tree.dart';

/// Left panel for the active repo: Branches (folder-grouped) · Remotes · Tags ·
/// Stashes. Read-only rows; sections collapse and their state persists.
class RepoSidebar extends ConsumerWidget {
  final VoidCallback onCollapse;
  const RepoSidebar({super.key, required this.onCollapse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final path = ref.watch(workspaceProvider).activeTab?.path;

    return Container(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(title: 'Repository', onCollapse: onCollapse),
          Expanded(
            child: path == null
                ? const SizedBox.shrink()
                : ref
                      .watch(repoDataProvider(path))
                      .when(
                        loading: () => const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        error: (e, _) => _LoadError(
                          onRetry: () => ref.invalidate(repoDataProvider(path)),
                        ),
                        data: (d) => _Sections(data: d),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback onCollapse;
  const _PanelHeader({required this.title, required this.onCollapse});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            tooltip: 'Collapse',
            icon: const Icon(Icons.chevron_left),
            onPressed: onCollapse,
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: t.danger, size: 22),
          const SizedBox(height: 8),
          Text(
            'Could not read repository',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Sections extends ConsumerWidget {
  final RepoData data;
  const _Sections({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(
      settingsProvider.select((s) => s.collapsedSections),
    );
    final ctl = ref.read(settingsProvider.notifier);
    bool isOpen(String id) => !(collapsed[id] ?? false);
    final path = ref.watch(workspaceProvider).activeTab?.path;
    final actions = path == null ? null : ref.read(repoActionsProvider(path));

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        _Section(
          id: 'branches',
          icon: Icons.call_split,
          label: 'Branches',
          count: data.branches.length,
          emptyLabel: 'No branches',
          open: isOpen('branches'),
          onToggle: () => ctl.toggleSection('branches'),
          children: [
            for (final row in buildBranchTree(data.branches, collapsed))
              if (row is BranchFolderRow)
                _FolderRow(
                  label: row.name,
                  depth: row.depth,
                  open: row.open,
                  onToggle: () => ctl.toggleSection(row.id),
                )
              else if (row is BranchLeafRow)
                _BranchRow(branch: row.branch, depth: row.depth),
          ],
        ),
        _Section(
          id: 'remotes',
          icon: Icons.cloud_outlined,
          label: 'Remotes',
          count: data.remoteBranches.length,
          emptyLabel: 'No remotes',
          open: isOpen('remotes'),
          onToggle: () => ctl.toggleSection('remotes'),
          children: [
            for (final r in data.remotes) ...[
              _LeafRow(
                icon: Icons.dns_outlined,
                label: r,
                onMenu: actions == null
                    ? null
                    : (at) => _remoteMenu(context, actions, r, at),
              ),
              for (final rb in data.remoteBranches.where((b) => b.remote == r))
                _RemoteBranchRow(
                  rb: rb,
                  onCheckout: actions == null
                      ? null
                      : () => actions.checkoutRemote(rb),
                  onMenu: actions == null
                      ? null
                      : (at) => _remoteBranchMenu(
                          context,
                          ref,
                          actions,
                          rb,
                          at,
                          currentLocal: data.branches
                              .where((b) => b.current && b.name == rb.branch)
                              .firstOrNull,
                        ),
                ),
            ],
          ],
        ),
        _Section(
          id: 'tags',
          icon: Icons.sell_outlined,
          label: 'Tags',
          count: data.tags.length,
          emptyLabel: 'No tags',
          open: isOpen('tags'),
          onToggle: () => ctl.toggleSection('tags'),
          children: [
            for (final tag in data.tags)
              _LeafRow(
                icon: Icons.local_offer_outlined,
                label: tag,
                onMenu: actions == null
                    ? null
                    : (at) => _tagMenu(context, ref, actions, tag, at),
              ),
          ],
        ),
        _Section(
          id: 'stashes',
          icon: Icons.inventory_2_outlined,
          label: 'Stashes',
          count: data.stashes.length,
          emptyLabel: 'No stashes',
          open: isOpen('stashes'),
          onToggle: () => ctl.toggleSection('stashes'),
          children: [
            for (final s in data.stashes)
              _LeafRow(
                icon: Icons.archive_outlined,
                label: s.message.isEmpty ? s.ref : s.message,
                trailing: actions == null
                    ? const []
                    : [
                        _MiniButton(
                          'Pop',
                          accent: true,
                          onTap: () => actions.stashPop(s.ref),
                        ),
                        _MiniButton(
                          'Apply',
                          onTap: () => actions.stashApply(s.ref),
                        ),
                      ],
                onMenu: actions == null
                    ? null
                    : (at) => _stashMenu(context, ref, actions, s, at),
              ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String id;
  final IconData icon;
  final String label;
  final int count;
  final bool open;
  final String emptyLabel;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _Section({
    required this.id,
    required this.icon,
    required this.label,
    required this.count,
    required this.emptyLabel,
    required this.open,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          hoverColor: t.hover,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 4),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: t.textFaint,
                ),
                const SizedBox(width: 2),
                Icon(icon, size: 14, color: t.textMuted),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(color: t.textFaint, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        if (open && children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 2, 12, 4),
            child: Text(
              emptyLabel,
              style: TextStyle(color: t.textFaint, fontSize: 12),
            ),
          ),
        if (open) ...children,
      ],
    );
  }
}

double _indent(int depth) => 30 + depth * 14;

class _FolderRow extends StatelessWidget {
  final String label;
  final int depth;
  final bool open;
  final VoidCallback onToggle;
  const _FolderRow({
    required this.label,
    required this.depth,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onToggle,
      hoverColor: t.hover,
      child: Padding(
        padding: EdgeInsets.fromLTRB(_indent(depth), 5, 12, 5),
        child: Row(
          children: [
            Icon(
              open ? Icons.expand_more : Icons.chevron_right,
              size: 15,
              color: t.textFaint,
            ),
            const SizedBox(width: 4),
            Icon(Icons.folder_outlined, size: 14, color: t.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether [branch] can be reset to its remote: it must be the checked-out
/// branch and have an upstream to reset onto.
bool canResetToRemote(Branch branch) =>
    branch.current && branch.upstream.isNotEmpty;

/// Confirms, then hard-resets the current branch to [upstream], warning that
/// [ahead] unpushed commits will be dropped (recoverable via Undo).
Future<void> _confirmResetToRemote(
  WidgetRef ref,
  BuildContext context,
  RepoActions actions, {
  required String branchName,
  required String upstream,
  required int ahead,
}) async {
  final ok = await confirmDestructive(
    ref,
    context,
    title: 'Reset $branchName to $upstream?',
    body: ahead > 0
        ? '$ahead unpushed commit${ahead == 1 ? '' : 's'} on $branchName '
              'will be removed. This can be undone.'
        : '$branchName will be moved to $upstream. This can be undone.',
    confirmLabel: 'Reset',
  );
  if (ok) await actions.resetToRemote(upstream);
}

class _BranchRow extends ConsumerWidget {
  final Branch branch;
  final int depth;
  const _BranchRow({required this.branch, required this.depth});

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final path = ref.read(workspaceProvider).activeTab?.path;
    if (path == null) return;
    final actions = ref.read(repoActionsProvider(path));
    final t = context.tokens;

    PopupMenuItem<void> item(
      String label,
      VoidCallback onTap, {
      bool enabled = true,
      bool danger = false,
    }) => PopupMenuItem(
      height: 34,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: danger ? t.danger : null),
      ),
    );

    await showContextMenu<void>(
      context: context,
      position: at,
      items: [
        item(
          'Checkout',
          () => actions.checkout(branch.name),
          enabled: !branch.current,
        ),
        item('Merge into current', () => actions.merge(branch.name)),
        item('Rebase onto current', () {
          final current = ref
              .read(repoDataProvider(path))
              .valueOrNull
              ?.branches
              .where((b) => b.current)
              .firstOrNull;
          if (current != null) actions.rebaseOnto(branch.name, current.name);
        }),
        const PopupMenuDivider(),
        item('Set upstream…', () async {
          final up = await showInputDialog(
            context,
            title: 'Set upstream for ${branch.name}',
            label: 'e.g. origin/${branch.name}',
          );
          if (up != null) await actions.setUpstream(branch.name, up);
        }),
        if (canResetToRemote(branch))
          item(
            'Reset to remote…',
            () => _confirmResetToRemote(
              ref,
              context,
              actions,
              branchName: branch.name,
              upstream: branch.upstream,
              ahead: branch.ahead,
            ),
          ),
        item('Rename…', () async {
          final name = await showInputDialog(
            context,
            title: 'Rename branch',
            initial: branch.name,
          );
          if (name != null && name != branch.name) {
            await actions.renameBranch(branch.name, name);
          }
        }),
        const PopupMenuDivider(),
        item(
          'Delete branch',
          () async {
            final ok = await confirmDestructive(
              ref,
              context,
              title: 'Delete ${branch.name}?',
              body: 'The branch ref will be removed. This can be undone.',
              confirmLabel: 'Delete',
            );
            if (ok) await actions.deleteBranch(branch.name);
          },
          enabled: !branch.current,
          danger: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final leaf = branch.name.split('/').last;
    // Row is selected when its tip is the commit currently highlighted in the
    // graph — a single click on the branch selects (and flies to) that tip.
    final selected =
        branch.tip.isNotEmpty &&
        ref.watch(selectedCommitProvider) == branch.tip;
    final row = GestureDetector(
      // Double-click a branch to go to its state: check it out, or — for the
      // current branch that tracks a remote — reset it to that remote (with a
      // confirm, since unpushed commits are dropped).
      onDoubleTap: branch.current
          ? (canResetToRemote(branch)
                ? () {
                    final path = ref.read(workspaceProvider).activeTab?.path;
                    if (path == null) return;
                    _confirmResetToRemote(
                      ref,
                      context,
                      ref.read(repoActionsProvider(path)),
                      branchName: branch.name,
                      upstream: branch.upstream,
                      ahead: branch.ahead,
                    );
                  }
                : null)
          : () {
              final path = ref.read(workspaceProvider).activeTab?.path;
              if (path != null) {
                ref.read(repoActionsProvider(path)).checkout(branch.name);
              }
            },
      onSecondaryTapUp: (d) => _menu(context, ref, d.globalPosition),
      child: InkWell(
        hoverColor: t.hover,
        onTap: branch.tip.isEmpty
            ? null
            : () =>
                  ref.read(selectedCommitProvider.notifier).state = branch.tip,
        child: Container(
          color: selected ? t.active : null,
          padding: EdgeInsets.fromLTRB(_indent(depth), 5, 10, 5),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: t.branchColor(branch.ci),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        leaf,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: branch.current ? t.textPrimary : t.textMuted,
                          fontSize: 13,
                          fontWeight: branch.current
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (branch.current) const _HeadBadge(),
                  ],
                ),
              ),
              if (branch.ahead > 0) _TrackBadge(icon: '↑', n: branch.ahead),
              if (branch.behind > 0) _TrackBadge(icon: '↓', n: branch.behind),
            ],
          ),
        ),
      ),
    );

    // Drag this branch onto another to open a Merge/Rebase menu; highlight
    // while a compatible branch hovers over this row.
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != branch.name,
      onAcceptWithDetails: (d) =>
          _dropMenu(context, ref, d.data, branch.name, d.offset),
      builder: (ctx, candidate, rejected) => Draggable<String>(
        data: branch.name,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragChip(label: leaf),
        childWhenDragging: Opacity(opacity: 0.4, child: row),
        child: Container(
          color: candidate.isNotEmpty ? t.accent.withValues(alpha: 0.14) : null,
          child: row,
        ),
      ),
    );
  }

  Future<void> _dropMenu(
    BuildContext context,
    WidgetRef ref,
    String source,
    String target,
    Offset at,
  ) async {
    final path = ref.read(workspaceProvider).activeTab?.path;
    if (path == null) return;
    final actions = ref.read(repoActionsProvider(path));
    await showContextMenu<void>(
      context: context,
      position: at,
      items: [
        PopupMenuItem(
          height: 34,
          onTap: () => actions.mergeInto(source, target),
          child: Text(
            'Merge «$source» into «$target»',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        PopupMenuItem(
          height: 34,
          onTap: () => actions.rebaseOnto(source, target),
          child: Text(
            'Rebase «$source» onto «$target»',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _DragChip extends StatelessWidget {
  final String label;
  const _DragChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_split, size: 12, color: t.accent),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: t.textPrimary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _HeadBadge extends StatelessWidget {
  const _HeadBadge();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'HEAD',
        style: TextStyle(
          color: t.accent,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _TrackBadge extends StatelessWidget {
  final String icon;
  final int n;
  const _TrackBadge({required this.icon, required this.n});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        '$icon$n',
        style: TextStyle(
          color: t.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One remote-tracking branch row, indented under its remote. Double-click or
/// the context menu checks it out (switching to the local branch or creating a
/// tracking one). A subtle dot marks branches that already have a local copy.
class _RemoteBranchRow extends ConsumerWidget {
  final RemoteBranch rb;
  final VoidCallback? onCheckout;
  final void Function(Offset at)? onMenu;
  const _RemoteBranchRow({
    required this.rb,
    required this.onCheckout,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final selected =
        rb.tip.isNotEmpty && ref.watch(selectedCommitProvider) == rb.tip;
    return GestureDetector(
      onSecondaryTapUp: onMenu == null
          ? null
          : (d) => onMenu!(d.globalPosition),
      onDoubleTap: onCheckout,
      child: Tooltip(
        message: rb.hasLocal
            ? 'Click to show its tip · double-click to switch to ${rb.branch}'
            : 'Click to show its tip · double-click to check out ${rb.name}',
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          hoverColor: t.hover,
          onTap: rb.tip.isEmpty
              ? null
              : () => ref.read(selectedCommitProvider.notifier).state = rb.tip,
          child: Container(
            color: selected ? t.active : null,
            padding: EdgeInsets.fromLTRB(_indent(1), 5, 10, 5),
            child: Row(
              children: [
                Icon(Icons.cloud_outlined, size: 13, color: t.textFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rb.branch,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textMuted, fontSize: 12.5),
                  ),
                ),
                if (rb.hasLocal)
                  Tooltip(
                    message: 'Has a local branch',
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _remoteBranchMenu(
  BuildContext context,
  WidgetRef ref,
  RepoActions actions,
  RemoteBranch rb,
  Offset at, {
  Branch? currentLocal,
}) async {
  await showContextMenu<void>(
    context: context,
    position: at,
    items: [
      PopupMenuItem(
        height: 34,
        onTap: () => actions.checkoutRemote(rb),
        child: Text(
          rb.hasLocal ? 'Switch to ${rb.branch}' : 'Check out ${rb.name}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
      PopupMenuItem(
        height: 34,
        onTap: () => actions.merge(rb.name),
        child: Text(
          'Merge ${rb.name} into current',
          style: const TextStyle(fontSize: 13),
        ),
      ),
      // Only when this remote branch's local counterpart is checked out —
      // resetting always acts on HEAD.
      if (currentLocal != null)
        PopupMenuItem(
          height: 34,
          onTap: () => _confirmResetToRemote(
            ref,
            context,
            actions,
            branchName: rb.branch,
            upstream: rb.name,
            ahead: currentLocal.ahead,
          ),
          child: Text(
            'Reset ${rb.branch} to this',
            style: const TextStyle(fontSize: 13),
          ),
        ),
    ],
  );
}

Future<void> _remoteMenu(
  BuildContext context,
  RepoActions actions,
  String remote,
  Offset at,
) async {
  await showContextMenu<void>(
    context: context,
    position: at,
    items: [
      PopupMenuItem(
        height: 34,
        onTap: () => actions.fetch(remote: remote),
        child: Text('Fetch $remote', style: const TextStyle(fontSize: 13)),
      ),
      PopupMenuItem(
        height: 34,
        onTap: () => actions.pruneRemote(remote),
        child: const Text('Prune', style: TextStyle(fontSize: 13)),
      ),
      PopupMenuItem(
        height: 34,
        onTap: () async {
          final url = await actions.remoteUrl(remote);
          if (url.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: url));
          }
        },
        child: const Text('Copy URL', style: TextStyle(fontSize: 13)),
      ),
    ],
  );
}

Future<void> _tagMenu(
  BuildContext context,
  WidgetRef ref,
  RepoActions actions,
  String tag,
  Offset at,
) async {
  final t = context.tokens;
  await showContextMenu<void>(
    context: context,
    position: at,
    items: [
      PopupMenuItem(
        height: 34,
        onTap: () => actions.checkout(tag),
        child: const Text('Checkout', style: TextStyle(fontSize: 13)),
      ),
      PopupMenuItem(
        height: 34,
        onTap: () => actions.pushTag(tag),
        child: const Text('Push tag', style: TextStyle(fontSize: 13)),
      ),
      PopupMenuItem(
        height: 34,
        onTap: () => Clipboard.setData(ClipboardData(text: tag)),
        child: const Text('Copy name', style: TextStyle(fontSize: 13)),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        height: 34,
        onTap: () async {
          final ok = await confirmDestructive(
            ref,
            context,
            title: 'Delete tag $tag?',
            body: 'The tag will be removed locally. This can be undone.',
            confirmLabel: 'Delete',
          );
          if (ok) await actions.deleteTag(tag);
        },
        child: Text(
          'Delete tag',
          style: TextStyle(fontSize: 13, color: t.danger),
        ),
      ),
    ],
  );
}

Future<void> _stashMenu(
  BuildContext context,
  WidgetRef ref,
  RepoActions actions,
  Stash stash,
  Offset at,
) async {
  final t = context.tokens;
  await showContextMenu<void>(
    context: context,
    position: at,
    items: [
      PopupMenuItem(
        height: 34,
        onTap: () => actions.stashPop(stash.ref),
        child: const Text('Pop', style: TextStyle(fontSize: 13)),
      ),
      PopupMenuItem(
        height: 34,
        onTap: () => actions.stashApply(stash.ref),
        child: const Text('Apply', style: TextStyle(fontSize: 13)),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        height: 34,
        onTap: () async {
          final ok = await confirmDestructive(
            ref,
            context,
            title: 'Drop ${stash.ref}?',
            body:
                'The stash will be deleted. An Undo toast lets you restore it.',
            confirmLabel: 'Drop',
          );
          if (ok) await actions.stashDrop(stash.ref);
        },
        child: Text('Drop', style: TextStyle(fontSize: 13, color: t.danger)),
      ),
    ],
  );
}

class _MiniButton extends StatelessWidget {
  final String label;
  final bool accent;
  final VoidCallback onTap;
  const _MiniButton(this.label, {required this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: accent ? t.accent.withValues(alpha: 0.16) : null,
            border: Border.all(color: accent ? Colors.transparent : t.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: accent ? t.accent : t.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _LeafRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final void Function(Offset at)? onMenu;
  final List<Widget> trailing;
  const _LeafRow({
    required this.icon,
    required this.label,
    this.onMenu,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onSecondaryTapUp: onMenu == null
          ? null
          : (d) => onMenu!(d.globalPosition),
      child: InkWell(
        hoverColor: t.hover,
        onTap: () {},
        child: Padding(
          padding: EdgeInsets.fromLTRB(_indent(0), 5, 10, 5),
          child: Row(
            children: [
              Icon(icon, size: 14, color: t.textFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textMuted, fontSize: 13),
                ),
              ),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}
