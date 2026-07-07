import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../graph/graph_view.dart';
import '../shell/resize_handle.dart';
import 'commit_details.dart';
import 'panel_placeholder.dart';
import 'repo_sidebar.dart';

/// The 3-panel workspace: left sidebar (refs) · centre (history/graph) · right
/// (changes). Left and right widths are user-resizable and persisted; the left
/// panel can collapse to a rail.
class WorkspaceView extends ConsumerWidget {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);

    return Row(
      children: [
        if (s.leftCollapsed)
          _CollapsedRail(onExpand: ctl.toggleLeftCollapsed)
        else ...[
          SizedBox(
            width: s.leftWidth,
            child: RepoSidebar(onCollapse: ctl.toggleLeftCollapsed),
          ),
          ResizeHandle(onDrag: (dx) => ctl.setLeftWidth(s.leftWidth + dx)),
        ],
        const Expanded(child: GraphView()),
        ResizeHandle(onDrag: (dx) => ctl.setRightWidth(s.rightWidth - dx)),
        SizedBox(width: s.rightWidth, child: const _RightPanel()),
      ],
    );
  }
}

/// Right panel: details of the selected commit; otherwise the working-tree
/// placeholder (staging lands in a later stage).
class _RightPanel extends ConsumerWidget {
  const _RightPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final path = ref.watch(workspaceProvider).activeTab?.path;
    final selected = ref.watch(selectedCommitProvider);

    if (path != null && selected != null && selected != wipSelection) {
      final data = ref.watch(repoDataProvider(path)).valueOrNull;
      Commit? commit;
      if (data != null) {
        for (final c in data.commits) {
          if (c.sha == selected) {
            commit = c;
            break;
          }
        }
      }
      if (commit != null) {
        return CommitDetails(
          repoPath: path,
          commit: commit,
          hasWip: data!.working.isNotEmpty,
        );
      }
    }
    return PanelPlaceholder(
      title: 'Changes',
      hint: 'Working tree · staging · commit',
      background: t.bgPanel,
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
