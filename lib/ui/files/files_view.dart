import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings_controller.dart';
import '../shell/collapsed_rail.dart';
import '../shell/resize_handle.dart';
import 'file_editor_pane.dart';
import 'project_nav_panel.dart';

/// Files mode: the project navigator on the left, the file editor on the
/// right. Replaces the history workspace for a tab, keeping the surrounding
/// app chrome in place.
class FilesView extends ConsumerWidget {
  final String repoPath;
  const FilesView({super.key, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = ref.watch(settingsProvider.select((s) => s.filesNavWidth));
    final collapsed = ref.watch(
      settingsProvider.select((s) => s.filesNavCollapsed),
    );
    final ctl = ref.read(settingsProvider.notifier);

    return Row(
      children: [
        if (collapsed)
          CollapsedRail(onExpand: ctl.toggleFilesNavCollapsed)
        else ...[
          SizedBox(
            width: width,
            child: ProjectNavPanel(
              repoPath: repoPath,
              onCollapse: ctl.toggleFilesNavCollapsed,
            ),
          ),
          ResizeHandle(onDrag: (dx) => ctl.setFilesNavWidth(width + dx)),
        ],
        Expanded(child: FileEditorPane(repoPath: repoPath)),
      ],
    );
  }
}
