import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diff_target.dart';
import 'file_editor.dart';

/// Unsaved text typed into the diff sheet's editor, one entry per file it was
/// typed into. Held here rather than in the editor so the text outlives it:
/// opening another file, switching tabs, Files mode and the dashboard all take
/// the editor away, and the text has to be there when it is back. Only saving
/// or a discard the user agreed to removes an entry.
///
/// Kept in the order the entries were last typed into, so the last one for a
/// repository is the one the user was working on.
class DiffDrafts extends StateNotifier<Map<DiffTarget, EditorDraft>> {
  DiffDrafts() : super(const {});

  /// Entries are per file, not per way of viewing it: typing into the file in
  /// whole-file view, or from its other side, continues the same draft.
  void put(DiffTarget target, EditorDraft draft) {
    state = {
      for (final e in state.entries)
        if (!editsSameFile(e.key, target)) e.key: e.value,
      target: draft,
    };
  }

  void drop(DiffTarget target) {
    if (!state.keys.any((t) => editsSameFile(t, target))) return;
    state = {
      for (final e in state.entries)
        if (!editsSameFile(e.key, target)) e.key: e.value,
    };
  }

  void dropRepo(String repoPath) {
    if (!state.keys.any((t) => t.repoPath == repoPath)) return;
    state = {
      for (final e in state.entries)
        if (e.key.repoPath != repoPath) e.key: e.value,
    };
  }
}

/// Whether [a] and [b] would edit the same file. Only working-tree diffs are
/// editable, and both sides of one — staged and unstaged — edit the same file
/// on disk; whole-file mode is only a way of looking at it.
bool editsSameFile(DiffTarget a, DiffTarget b) =>
    a.isWorkingTree &&
    b.isWorkingTree &&
    a.repoPath == b.repoPath &&
    a.path == b.path;

/// The unsaved text for [target]'s file, however its diff is being viewed.
EditorDraft? draftFor(Map<DiffTarget, EditorDraft> drafts, DiffTarget target) {
  for (final e in drafts.entries) {
    if (editsSameFile(e.key, target)) return e.value;
  }
  return null;
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
