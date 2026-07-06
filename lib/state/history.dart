/// Generic undo/redo history.
///
/// Holds snapshots of some immutable state [T]. Before a mutating action,
/// call [push] with the *current* snapshot; that clears the redo stack.
/// [undo]/[redo] swap the current state with the neighbouring snapshot.
class History<T> {
  final List<T> _past = [];
  final List<T> _future = [];
  final int cap;

  History({this.cap = 40});

  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  int get undoDepth => _past.length;
  int get redoDepth => _future.length;

  /// Record [snapshot] (the state *before* a mutation) and clear redo.
  void push(T snapshot) {
    _past.add(snapshot);
    if (_past.length > cap) _past.removeAt(0);
    _future.clear();
  }

  /// Returns the state to restore, or null if nothing to undo.
  /// [current] is pushed onto the redo stack.
  T? undo(T current) {
    if (_past.isEmpty) return null;
    _future.insert(0, current);
    if (_future.length > cap) _future.removeLast();
    return _past.removeLast();
  }

  /// Returns the state to restore, or null if nothing to redo.
  T? redo(T current) {
    if (_future.isEmpty) return null;
    _past.add(current);
    if (_past.length > cap) _past.removeAt(0);
    return _future.removeAt(0);
  }

  void clear() {
    _past.clear();
    _future.clear();
  }
}
