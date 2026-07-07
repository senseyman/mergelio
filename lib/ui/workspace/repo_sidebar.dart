import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
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
          count: data.remotes.length,
          emptyLabel: 'No remotes',
          open: isOpen('remotes'),
          onToggle: () => ctl.toggleSection('remotes'),
          children: [
            for (final r in data.remotes)
              _LeafRow(icon: Icons.dns_outlined, label: r),
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
              _LeafRow(icon: Icons.local_offer_outlined, label: tag),
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

class _BranchRow extends StatelessWidget {
  final Branch branch;
  final int depth;
  const _BranchRow({required this.branch, required this.depth});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final leaf = branch.name.split('/').last;
    return InkWell(
      hoverColor: t.hover,
      onTap: () {},
      child: Padding(
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

class _LeafRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _LeafRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
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
          ],
        ),
      ),
    );
  }
}
