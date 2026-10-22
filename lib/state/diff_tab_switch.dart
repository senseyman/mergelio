import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diff_drafts.dart';
import 'diff_target.dart';
import 'file_editor.dart';
import 'workspace.dart';

/// Keeps the diff sheet with its own repository. Switching tabs puts the sheet
/// away, since the file it shows belongs to the repository being left. Unsaved
/// text in its editor is set aside rather than dropped — the other repository
/// is free to open diffs of its own meanwhile — and comes back, still in the
/// editor, when its repository is active again.
final diffTabSwitchProvider = Provider<void>((ref) {
  void putAway() {
    ref.read(diffEditorDirtyProvider.notifier).state = false;
    ref.read(diffEditingProvider.notifier).state = null;
    ref.read(diffTargetProvider.notifier).state = null;
  }

  ref.listen(workspaceProvider.select((w) => w.activeTab?.path), (_, next) {
    final target = ref.read(diffTargetProvider);
    if (target != null && target.repoPath != next) {
      // The editor has already left its text in the store, so putting the
      // sheet away is all it takes to set it aside.
      putAway();
    }
    if (next == null || ref.read(diffTargetProvider) != null) return;
    final draft = ref.read(diffDraftsProvider)[next];
    if (draft == null) return;
    ref.read(diffTargetProvider.notifier).state = draft.target;
    ref.read(diffEditingProvider.notifier).state = draft.target;
    ref.read(diffEditorDirtyProvider.notifier).state = true;
  });

  // Edits set aside for a repository that is no longer open have nowhere to
  // come back to; closing its tab has already asked about them.
  ref.listen(
    workspaceProvider.select((w) => w.tabs.map((t) => t.path).join('\n')),
    (_, _) {
      final open = {for (final t in ref.read(workspaceProvider).tabs) t.path};
      final drafts = ref.read(diffDraftsProvider.notifier);
      for (final repo in [...ref.read(diffDraftsProvider).keys]) {
        if (!open.contains(repo)) drafts.drop(repo);
      }
    },
  );

  // Another file opened in the same repository replaces the one being edited,
  // so a draft for the old one would come back over the new one.
  ref.listen(diffTargetProvider, (_, next) {
    if (next == null) return;
    final draft = ref.read(diffDraftsProvider)[next.repoPath];
    if (draft != null && draft.target != next) {
      ref.read(diffDraftsProvider.notifier).drop(next.repoPath);
    }
  });
});
