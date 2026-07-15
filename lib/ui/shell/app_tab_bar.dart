import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../common/dialogs.dart';
import '../welcome/open_repo.dart';
import '../welcome/repo_dialogs.dart';

/// Repo tabs strip with the group switcher. The switcher style (dropdown /
/// pills / side rail) comes from settings; the rail variant renders in the
/// app shell as [GroupRail] and the strip then shows tabs only.
class AppTabBar extends ConsumerWidget {
  const AppTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ws = ref.watch(workspaceProvider);
    final style = ref.watch(settingsProvider.select((s) => s.groupStyle));

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: t.bgApp,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          if (ws.tabs.isNotEmpty && style == 'dropdown') _GroupDropdown(ws: ws),
          if (ws.tabs.isNotEmpty && style == 'pills') _GroupPills(ws: ws),
          if (ws.tabs.isNotEmpty && style != 'rail')
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: t.border,
            ),
          // The strip scrolls when tabs overflow instead of clipping.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in ws.visibleTabs)
                    _Tab(tab: tab, active: tab.id == ws.activeTabId),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Add repository',
            position: PopupMenuPosition.under,
            onSelected: (v) {
              switch (v) {
                case 'open':
                  openRepositoryFlow(context, ref);
                case 'clone':
                  showCloneDialog(context);
                case 'create':
                  showCreateDialog(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'open',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.folder_open_outlined, size: 16),
                    SizedBox(width: 10),
                    Text('Open…', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clone',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.cloud_download_outlined, size: 16),
                    SizedBox(width: 10),
                    Text('Clone…', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'create',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.add_box_outlined, size: 16),
                    SizedBox(width: 10),
                    Text('Create…', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
            child: const SizedBox(
              width: 28,
              height: 28,
              child: Icon(Icons.add, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "group ▾" menu: All + each group + New group.
class _GroupDropdown extends ConsumerWidget {
  final WorkspaceState ws;
  const _GroupDropdown({required this.ws});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ctl = ref.read(workspaceProvider.notifier);
    final active = ws.groupById(ws.activeGroupId);

    return PopupMenuButton<Object>(
      tooltip: 'Repo group',
      onSelected: (v) async {
        if (v == 'all') {
          ctl.setActiveGroup(null);
        } else if (v == 'new') {
          final name = await showInputDialog(
            context,
            title: 'New group',
            label: 'Group name',
          );
          if (name != null && name.trim().isNotEmpty) {
            ctl.setActiveGroup(ctl.createGroup(name.trim()).id);
          }
        } else if (v is int) {
          ctl.setActiveGroup(v);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'all',
          height: 34,
          child: Text('All', style: TextStyle(fontSize: 13)),
        ),
        for (final g in ws.groups)
          PopupMenuItem(
            value: g.id,
            height: 34,
            child: Row(
              children: [
                _GroupDot(color: Color(g.colorValue)),
                const SizedBox(width: 8),
                Text(g.name, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'new',
          height: 34,
          child: Text('New group…', style: TextStyle(fontSize: 13)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active != null) ...[
              _GroupDot(color: Color(active.colorValue)),
              const SizedBox(width: 6),
            ],
            Text(
              active?.name ?? 'All',
              style: TextStyle(color: t.textMuted, fontSize: 12.5),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: t.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Pill per group (+ All and a + pill), right-click a pill to manage it.
class _GroupPills extends ConsumerWidget {
  final WorkspaceState ws;
  const _GroupPills({required this.ws});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ctl = ref.read(workspaceProvider.notifier);

    Widget pill({
      required String label,
      Color? dot,
      required bool selected,
      required VoidCallback onTap,
      GestureTapDownCallback? onContext,
    }) => GestureDetector(
      onSecondaryTapDown: onContext,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.rPill),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: selected ? t.active : null,
              borderRadius: BorderRadius.circular(t.rPill),
              border: Border.all(color: selected ? t.accent : t.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[
                  _GroupDot(color: dot),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: selected ? t.accent : t.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Future<void> manage(RepoGroup g, Offset at) async {
      final action = await showContextMenu<String>(
        context: context,
        position: at,
        items: const [
          PopupMenuItem(value: 'rename', height: 34, child: Text('Rename')),
          PopupMenuItem(
            value: 'delete',
            height: 34,
            child: Text('Delete group'),
          ),
        ],
      );
      if (!context.mounted) return;
      switch (action) {
        case 'rename':
          final name = await showInputDialog(
            context,
            title: 'Rename group',
            label: 'Group name',
          );
          if (name != null && name.trim().isNotEmpty) {
            ctl.renameGroup(g.id, name.trim());
          }
        case 'delete':
          ctl.deleteGroup(g.id);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill(
          label: 'All',
          selected: ws.activeGroupId == null,
          onTap: () => ctl.setActiveGroup(null),
        ),
        for (final g in ws.groups)
          pill(
            label: g.name,
            dot: Color(g.colorValue),
            selected: ws.activeGroupId == g.id,
            onTap: () => ctl.setActiveGroup(g.id),
            onContext: (d) => manage(g, d.globalPosition),
          ),
        pill(
          label: '+',
          selected: false,
          onTap: () async {
            final name = await showInputDialog(
              context,
              title: 'New group',
              label: 'Group name',
            );
            if (name != null && name.trim().isNotEmpty) {
              ctl.setActiveGroup(ctl.createGroup(name.trim()).id);
            }
          },
        ),
      ],
    );
  }
}

/// Vertical group rail for the 'rail' switcher style, docked at the far left
/// of the shell: one colour-dot button per group plus All and New.
class GroupRail extends ConsumerWidget {
  const GroupRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ws = ref.watch(workspaceProvider);
    final ctl = ref.read(workspaceProvider.notifier);
    if (ws.tabs.isEmpty) return const SizedBox.shrink();

    Widget item({
      required Widget child,
      required String tooltip,
      required bool selected,
      required VoidCallback onTap,
    }) => Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.active : null,
            borderRadius: BorderRadius.circular(8),
            border: selected ? Border.all(color: t.accent) : null,
          ),
          child: child,
        ),
      ),
    );

    return Container(
      width: 42,
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          item(
            child: Icon(Icons.apps, size: 15, color: t.textMuted),
            tooltip: 'All',
            selected: ws.activeGroupId == null,
            onTap: () => ctl.setActiveGroup(null),
          ),
          for (final g in ws.groups)
            item(
              child: _GroupDot(color: Color(g.colorValue), size: 10),
              tooltip: g.name,
              selected: ws.activeGroupId == g.id,
              onTap: () => ctl.setActiveGroup(g.id),
            ),
          item(
            child: Icon(Icons.add, size: 15, color: t.textFaint),
            tooltip: 'New group',
            selected: false,
            onTap: () async {
              final name = await showInputDialog(
                context,
                title: 'New group',
                label: 'Group name',
              );
              if (name != null && name.trim().isNotEmpty) {
                ctl.setActiveGroup(ctl.createGroup(name.trim()).id);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _GroupDot extends StatelessWidget {
  final Color color;
  final double size;
  const _GroupDot({required this.color, this.size = 8});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Tab extends ConsumerWidget {
  final RepoTab tab;
  final bool active;
  const _Tab({required this.tab, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ws = ref.watch(workspaceProvider);
    final ctl = ref.read(workspaceProvider.notifier);
    // Tab dot takes its group's colour; ungrouped tabs use the accent.
    final dotColor = Color(
      ws.groupById(tab.groupId)?.colorValue ?? t.accent.toARGB32(),
    );

    final content = Material(
      color: active ? t.bgPanel : Colors.transparent,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: InkWell(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        hoverColor: t.hover,
        onTap: () => ctl.setActive(tab.id),
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: active
              ? BoxDecoration(
                  border: Border(top: BorderSide(color: t.accent, width: 2)),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tab.name,
                style: TextStyle(
                  fontSize: 12.5,
                  color: active ? t.textPrimary : t.textMuted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => ctl.closeTab(tab.id),
                child: Icon(Icons.close, size: 13, color: t.textFaint),
              ),
            ],
          ),
        ),
      ),
    );

    // Tabs drag to reorder: each tab is both draggable and a drop target that
    // inserts the dragged tab before itself.
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != tab.id,
      onAcceptWithDetails: (d) {
        final tabs = ws.tabs;
        final from = tabs.indexWhere((x) => x.id == d.data);
        final to = tabs.indexWhere((x) => x.id == tab.id);
        if (from != -1 && to != -1) ctl.reorderTab(from, to);
      },
      builder: (context, candidates, _) => Draggable<int>(
        data: tab.id,
        axis: Axis.horizontal,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.85, child: content),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: content),
        child: GestureDetector(
          onSecondaryTapDown: (d) async {
            final action = await showContextMenu<String>(
              context: context,
              position: d.globalPosition,
              items: [
                const PopupMenuItem(
                  value: 'close',
                  height: 36,
                  child: Text('Close tab'),
                ),
                const PopupMenuItem(
                  value: 'others',
                  height: 36,
                  child: Text('Close others'),
                ),
                if (ws.groups.isNotEmpty) const PopupMenuDivider(),
                for (final g in ws.groups)
                  PopupMenuItem(
                    value: 'group:${g.id}',
                    height: 36,
                    child: Row(
                      children: [
                        _GroupDot(color: Color(g.colorValue)),
                        const SizedBox(width: 8),
                        Text(
                          tab.groupId == g.id
                              ? 'Remove from ${g.name}'
                              : 'Move to ${g.name}',
                        ),
                      ],
                    ),
                  ),
              ],
            );
            if (action == null) return;
            switch (action) {
              case 'close':
                ctl.closeTab(tab.id);
              case 'others':
                ctl.closeOthers(tab.id);
              default:
                if (action.startsWith('group:')) {
                  final gid = int.parse(action.substring(6));
                  ctl.moveToGroup(tab.id, tab.groupId == gid ? null : gid);
                }
            }
          },
          child: Container(
            decoration: candidates.isNotEmpty
                ? BoxDecoration(
                    border: Border(left: BorderSide(color: t.accent, width: 2)),
                  )
                : null,
            child: content,
          ),
        ),
      ),
    );
  }
}
