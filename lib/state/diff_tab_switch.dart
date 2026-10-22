import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diff_target.dart';
import 'file_editor.dart';
import 'workspace.dart';

/// Puts the diff sheet away when another repository becomes active: the file
/// it shows belongs to the one being left. A sheet whose editor holds unsaved
/// text stays open instead — hidden while its repository is in the background
/// and shown again on return — so switching tabs never drops typed text.
final diffTabSwitchProvider = Provider<void>((ref) {
  ref.listen(workspaceProvider.select((w) => w.activeTab?.path), (_, next) {
    final target = ref.read(diffTargetProvider);
    if (target == null || target.repoPath == next) return;
    if (ref.read(diffEditingProvider) == target &&
        ref.read(diffEditorDirtyProvider)) {
      return;
    }
    ref.read(diffEditorDirtyProvider.notifier).state = false;
    ref.read(diffEditingProvider.notifier).state = null;
    ref.read(diffTargetProvider.notifier).state = null;
  });
});
