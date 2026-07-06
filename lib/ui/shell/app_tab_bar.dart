import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/workspace.dart';
import '../common/dialogs.dart';
import '../welcome/open_repo.dart';

/// Repo tabs strip. Group switcher arrives with multi-group support.
class AppTabBar extends ConsumerWidget {
  const AppTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ws = ref.watch(workspaceProvider);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: t.bgApp,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          for (final tab in ws.tabs)
            _Tab(tab: tab, active: tab.id == ws.activeTabId),
          Tooltip(
            message: 'Open repository',
            child: InkWell(
              borderRadius: BorderRadius.circular(t.rButton),
              hoverColor: t.hover,
              onTap: () => openRepositoryFlow(context, ref),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.add, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends ConsumerWidget {
  final RepoTab tab;
  final bool active;
  const _Tab({required this.tab, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ctl = ref.read(workspaceProvider.notifier);

    return GestureDetector(
      onSecondaryTapDown: (d) async {
        final action = await showContextMenu<String>(
          context: context,
          position: d.globalPosition,
          items: const [
            PopupMenuItem(value: 'close', height: 36, child: Text('Close tab')),
            PopupMenuItem(
              value: 'others',
              height: 36,
              child: Text('Close others'),
            ),
          ],
        );
        switch (action) {
          case 'close':
            ctl.closeTab(tab.id);
          case 'others':
            ctl.closeOthers(tab.id);
        }
      },
      child: Material(
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
                    color: t.accent,
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
      ),
    );
  }
}
