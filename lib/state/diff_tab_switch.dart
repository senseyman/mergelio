import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diff_drafts.dart';
import 'diff_target.dart';
import 'file_editor.dart';
import 'workspace.dart';

/// Keeps the diff sheet's editing state in step with the diff it shows, and
/// the sheet with its own repository.
///
/// Opening any diff puts it in edit mode if it holds unsaved text and out of
/// it otherwise, so the editing target, the dirty flag and the stored text
/// always move together. Text typed into the diff being left stays in the
/// store and comes back with that diff.
///
/// Switching tabs puts the sheet away, since the file it shows belongs to the
/// repository being left; coming back reopens the diff last edited there.
final diffTabSwitchProvider = Provider<void>((ref) {
  ref.listen(diffTargetProvider, (_, next) {
    final hasDraft = next != null && ref.read(diffDraftsProvider)[next] != null;
    ref.read(diffEditingProvider.notifier).state = hasDraft ? next : null;
    ref.read(diffEditorDirtyProvider.notifier).state = hasDraft;
  });

  ref.listen(workspaceProvider.select((w) => w.activeTab?.path), (_, next) {
    final target = ref.read(diffTargetProvider);
    if (target != null && target.repoPath != next) {
      ref.read(diffTargetProvider.notifier).state = null;
    }
    if (next == null || ref.read(diffTargetProvider) != null) return;
    final edited = draftTargetsIn(ref.read(diffDraftsProvider), next);
    if (edited.isEmpty) return;
    ref.read(diffTargetProvider.notifier).state = edited.last;
  });

  // Edits for a repository that is no longer open have nowhere to come back
  // to; closing its tab has already asked about them. NUL cannot appear in a
  // path, so it keeps the joined key unambiguous.
  ref.listen(
    workspaceProvider.select((w) => w.tabs.map((t) => t.path).join('\u0000')),
    (_, _) {
      final open = {for (final t in ref.read(workspaceProvider).tabs) t.path};
      final drafts = ref.read(diffDraftsProvider.notifier);
      for (final repo in {
        for (final t in ref.read(diffDraftsProvider).keys) t.repoPath,
      }) {
        if (!open.contains(repo)) drafts.dropRepo(repo);
      }
    },
  );
});
