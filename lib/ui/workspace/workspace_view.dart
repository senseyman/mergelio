import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_data.dart';
import '../../state/settings.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../../state/diff_target.dart';
import '../diff/diff_sheet.dart';
import '../files/files_view.dart';
import '../merge/merge_tool.dart';
import '../graph/graph_view.dart';
import '../shell/collapsed_rail.dart';
import '../shell/resize_handle.dart';
import '../../state/compare_target.dart';
import '../../state/review.dart';
import '../review/review_view.dart';
import 'commit_details.dart';
import 'lfs_locks_section.dart';
import 'compare_details.dart';
import 'panel_placeholder.dart';
import 'repo_sidebar.dart';
import 'stash_panel.dart';
import 'working_tree_panel.dart';
import '../../l10n/gen/app_localizations.dart';

/// The 3-panel workspace: left sidebar (refs) · centre (history/graph) · right
/// (changes). Left and right widths are user-resizable and persisted; the left
/// panel can collapse to a rail.
class WorkspaceView extends ConsumerWidget {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final tab = ref.watch(workspaceProvider.select((w) => w.activeTab));
    final Widget view;
    if (tab != null && tab.viewMode == RepoViewMode.files) {
      view = MergeToolGate(child: FilesView(repoPath: tab.path));
    } else {
      view = _panels(s, ctl);
    }
    return tab == null
        ? view
        : LfsLocksUnsupportedNotice(repoPath: tab.path, child: view);
  }

  Widget _panels(AppSettings s, SettingsController ctl) => MergeToolGate(
    child: Row(
      children: [
        if (s.leftCollapsed)
          CollapsedRail(onExpand: ctl.toggleLeftCollapsed)
        else ...[
          SizedBox(
            width: s.leftWidth,
            child: RepoSidebar(onCollapse: ctl.toggleLeftCollapsed),
          ),
          ResizeHandle(onDrag: (dx) => ctl.setLeftWidth(s.leftWidth + dx)),
        ],
        const Expanded(child: _CenterWithDiff()),
        ResizeHandle(onDrag: (dx) => ctl.setRightWidth(s.rightWidth - dx)),
        SizedBox(width: s.rightWidth, child: const RightPanel()),
      ],
    ),
  );
}

/// Centre column: the graph, with the diff sheet sliding up over its lower
/// portion. Clicking the visible graph strip closes an open sheet.
class _CenterWithDiff extends ConsumerWidget {
  const _CenterWithDiff();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(diffTargetProvider) != null;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: open
                  ? () => ref.read(diffTargetProvider.notifier).state = null
                  : null,
              child: const _CenterContent(),
            ),
          ),
          // The sheet slides up from the bottom edge (~240ms ease-out) and
          // stays mounted during the exit slide.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: open ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: open
                  ? DiffSheet(availableHeight: box.maxHeight)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the centre column shows under the diff sheet: an open review of this
/// repository, else the graph. A review left open in another tab stays there.
class _CenterContent extends ConsumerWidget {
  const _CenterContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(workspaceProvider).activeTab?.path;
    final review = ref.watch(reviewTargetProvider);
    if (review != null && review.repoPath == path) return const ReviewView();
    return const GraphView();
  }
}

/// Right panel: the comparison being read, else details of the selected
/// commit, else the working tree.
class RightPanel extends ConsumerWidget {
  const RightPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final path = ref.watch(workspaceProvider).activeTab?.path;
    final selected = ref.watch(selectedCommitProvider);

    // Picking a commit anywhere — graph, sidebar, palette — is a request for
    // that commit, so it puts an open comparison away instead of leaving the
    // panel stuck on it.
    ref.listen(selectedCommitProvider, (_, _) {
      ref.read(compareTargetProvider.notifier).state = null;
    });

    // A comparison is the question the user asked last, so until it is closed
    // it outranks the selection. One left over from another repository is not
    // this repository's answer, so it stays hidden.
    final compare = ref.watch(compareTargetProvider);
    if (compare != null && compare.repoPath == path) {
      return const CompareDetails();
    }

    if (path != null && selected != null && selected != wipSelection) {
      final data = ref.watch(repoDataProvider(path)).valueOrNull;
      // A stash is a commit too, but what it is for is getting the work back,
      // so it gets its own panel rather than a commit's details.
      final stash = data?.stashes.where((s) => s.sha == selected).firstOrNull;
      if (stash != null) return StashPanel(repoPath: path, stash: stash);
      Commit? commit;
      if (data != null) {
        for (final c in data.commits) {
          if (c.sha == selected) {
            commit = c;
            break;
          }
        }
      }
      // Not on the loaded page — picked from the reflog, a review or a
      // signature check — so read that one commit on its own. The working
      // tree stays up while it loads, and for a sha the repository lacks.
      if (commit == null && data != null) {
        commit = ref
            .watch(commitByShaProvider((repo: path, sha: selected)))
            .valueOrNull;
      }
      if (commit != null) {
        return CommitDetails(
          repoPath: path,
          commit: commit,
          hasWip: data!.working.isNotEmpty,
        );
      }
    }
    if (path != null) {
      final data = ref.watch(repoDataProvider(path)).valueOrNull;
      if (data != null) {
        return WorkingTreePanel(repoPath: path, data: data);
      }
    }
    return PanelPlaceholder(
      title: l.wvChanges,
      hint: l.wvChangesSub,
      background: t.bgPanel,
    );
  }
}
