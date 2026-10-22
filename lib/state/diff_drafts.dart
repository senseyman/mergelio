import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diff_target.dart';
import 'file_editor.dart';

/// Unsaved text typed into the diff sheet's editor, one entry per diff it was
/// typed into. Held here rather than in the editor so the text outlives it:
/// opening another file, switching tabs, Files mode and the dashboard all take
/// the editor away, and the text has to be there when it is back. Only saving
/// or a discard the user agreed to removes an entry.
///
/// Kept in the order the entries were last typed into, so the last one for a
/// repository is the one the user was working on.
class DiffDrafts extends StateNotifier<Map<DiffTarget, EditorDraft>> {
  DiffDrafts() : super(const {});

  void put(DiffTarget target, EditorDraft draft) {
    final next = {...state}..remove(target);
    state = next..[target] = draft;
  }

  void drop(DiffTarget target) {
    if (!state.containsKey(target)) return;
    state = {...state}..remove(target);
  }

  void dropRepo(String repoPath) {
    if (!state.keys.any((t) => t.repoPath == repoPath)) return;
    state = {
      for (final e in state.entries)
        if (e.key.repoPath != repoPath) e.key: e.value,
    };
  }
}

/// The diffs in [repoPath] holding unsaved text, oldest first.
List<DiffTarget> draftTargetsIn(
  Map<DiffTarget, EditorDraft> drafts,
  String repoPath,
) => [
  for (final t in drafts.keys)
    if (t.repoPath == repoPath) t,
];

final diffDraftsProvider =
    StateNotifierProvider<DiffDrafts, Map<DiffTarget, EditorDraft>>(
      (ref) => DiffDrafts(),
    );
