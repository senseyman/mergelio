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
      await entry.undo();
      state = UndoState(
        past: state.past.sublist(0, state.past.length - 1),
        future: [...state.future, entry],
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
      await entry.redo();
      state = UndoState(
        past: [...state.past, entry],
        future: state.future.sublist(0, state.future.length - 1),
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
