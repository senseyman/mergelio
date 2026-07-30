import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One reversible action: [undo] restores the pre-op state, [redo] re-applies
/// it. Both are real git operations (reflog-friendly), not state snapshots.
class UndoEntry {
  final String label;
  final Future<void> Function() undo;
  final Future<void> Function() redo;
  const UndoEntry(this.label, {required this.undo, required this.redo});
}

/// Immutable undo history: [past] can be undone, [future] can be redone.
class UndoState {
  final List<UndoEntry> past;
  final List<UndoEntry> future;
  const UndoState({this.past = const [], this.future = const []});

  bool get canUndo => past.isNotEmpty;
  bool get canRedo => future.isNotEmpty;
  String? get undoLabel => past.isEmpty ? null : past.last.label;
  String? get redoLabel => future.isEmpty ? null : future.last.label;
}

/// Per-repo undo/redo history. Recording a new action clears the redo future
/// (linear history). Undo/redo run the entry's git op and move it across the
/// stacks.
class UndoController extends StateNotifier<UndoState> {
  UndoController() : super(const UndoState());

  static const _cap = 40;

  // Guards against re-entrancy: undo/redo await a git op before mutating the
  // stacks, so an auto-repeated ⌘Z (or button + key) must not double-run the
  // same entry and corrupt the history.
  bool _running = false;

  void record(UndoEntry entry) {
    final past = [...state.past, entry];
    if (past.length > _cap) past.removeRange(0, past.length - _cap);
    state = UndoState(past: past, future: const []);
  }

  Future<void> undo() async {
    if (_running || state.past.isEmpty) return;
    _running = true;
    try {
      final entry = state.past.last;
      final before = state;
      await entry.undo();
      // record() may run during the await (the op itself recording a
      // follow-up action). Remove the undone entry by identity rather than
      // splicing off the last slot, and only offer it for redo when nothing
      // intervened — a new recording clears the redo future.
      final intervened = !identical(state, before);
      state = UndoState(
        past: [
          for (final e in state.past)
            if (!identical(e, entry)) e,
        ],
        future: intervened ? state.future : [...state.future, entry],
      );
    } finally {
      _running = false;
    }
  }

  Future<void> redo() async {
    if (_running || state.future.isEmpty) return;
    _running = true;
    try {
      final entry = state.future.last;
      final before = state;
      await entry.redo();
      // Mirror of undo(): remove by identity, and only push onto past when
      // no recording intervened during the await.
      final intervened = !identical(state, before);
      state = UndoState(
        past: intervened ? state.past : [...state.past, entry],
        future: [
          for (final e in state.future)
            if (!identical(e, entry)) e,
        ],
      );
    } finally {
      _running = false;
    }
  }
}

final undoProvider =
    StateNotifierProvider.family<UndoController, UndoState, String>(
      (ref, path) => UndoController(),
    );
