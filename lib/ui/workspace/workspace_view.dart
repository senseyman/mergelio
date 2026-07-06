import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/settings_controller.dart';
import '../shell/resize_handle.dart';
import 'panel_placeholder.dart';

/// The 3-panel workspace: left sidebar (refs) · centre (history/graph) · right
/// (changes). Left and right widths are user-resizable and persisted; the left
/// panel can collapse to a rail.
class WorkspaceView extends ConsumerWidget {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);

    return Row(
      children: [
        if (s.leftCollapsed)
          _CollapsedRail(onExpand: ctl.toggleLeftCollapsed)
        else ...[
          SizedBox(
            width: s.leftWidth,
            child: PanelPlaceholder(
              title: 'Repository',
              hint: 'Branches · Remotes · Tags · Stashes',
              background: t.bgPanel,
              trailing: [
                IconButton(
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Collapse',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: ctl.toggleLeftCollapsed,
                ),
              ],
            ),
          ),
          ResizeHandle(onDrag: (dx) => ctl.setLeftWidth(s.leftWidth + dx)),
        ],
        Expanded(
          child: PanelPlaceholder(
            title: 'History',
            hint: 'Commit graph',
            background: t.bgApp,
          ),
        ),
        ResizeHandle(onDrag: (dx) => ctl.setRightWidth(s.rightWidth - dx)),
        SizedBox(
          width: s.rightWidth,
          child: PanelPlaceholder(
            title: 'Changes',
            hint: 'Working tree · staging · commit',
            background: t.bgPanel,
          ),
        ),
      ],
    );
  }
}

class _CollapsedRail extends StatelessWidget {
  final VoidCallback onExpand;
  const _CollapsedRail({required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 44,
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          IconButton(
            iconSize: 17,
            tooltip: 'Expand',
            icon: const Icon(Icons.chevron_right),
            onPressed: onExpand,
          ),
        ],
      ),
    );
  }
}
