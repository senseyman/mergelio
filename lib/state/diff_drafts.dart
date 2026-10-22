import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diff_target.dart';
import 'file_editor.dart';

/// Text typed into the diff sheet's editor that is not on disk yet, and the
/// diff it was typed into.
class DiffDraft {
  final DiffTarget target;
  final EditorDraft editor;
  const DiffDraft({required this.target, required this.editor});
}

/// Unsaved diff-sheet edits, one per repository — the sheet edits one file at
/// a time. Held here rather than in the editor so the text outlives it: a tab
/// switch puts the sheet away, Files mode and the dashboard take the whole
/// centre column down, and the text has to be there when the editor is back.
class DiffDrafts extends StateNotifier<Map<String, DiffDraft>> {
  DiffDrafts() : super(const {});

  void put(DiffDraft draft) => state = {...state, draft.target.repoPath: draft};

  void drop(String repoPath) {
    if (!state.containsKey(repoPath)) return;
    state = {...state}..remove(repoPath);
  }
}

final diffDraftsProvider =
    StateNotifierProvider<DiffDrafts, Map<String, DiffDraft>>(
      (ref) => DiffDrafts(),
    );
