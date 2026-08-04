import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The editor tabs of one repository: what is open, what is on top, what has
/// unsaved text, and what has disappeared from disk since it was opened.
class OpenFiles {
  /// Repo-relative paths, in tab-strip order.
  final List<String> paths;
  final String? active;

  /// Tabs holding text that is not on disk. Never persisted — a restart
  /// starts from what the files actually contain.
  final Set<String> dirty;

  /// Tabs whose file was deleted or moved away while it was open. Saving one
  /// would recreate a file the user removed, so it is refused instead.
  final Set<String> gone;

  const OpenFiles({
    this.paths = const [],
    this.active,
    this.dirty = const {},
    this.gone = const {},
  });

  bool isDirty(String path) => dirty.contains(path);
  bool isGone(String path) => gone.contains(path);

  OpenFiles _with({
    List<String>? paths,
    String? active,
    bool clearActive = false,
    Set<String>? dirty,
    Set<String>? gone,
  }) => OpenFiles(
    paths: paths ?? this.paths,
    active: clearActive ? null : (active ?? this.active),
    dirty: dirty ?? this.dirty,
    gone: gone ?? this.gone,
  );
}

class OpenFilesNotifier extends StateNotifier<OpenFiles> {
  OpenFilesNotifier() : super(const OpenFiles());

  /// Opens [path], or brings it forward when it is already open.
  void open(String path) {
    state = state._with(
      paths: state.paths.contains(path) ? null : [...state.paths, path],
      active: path,
    );
  }

  void activate(String path) {
    if (!state.paths.contains(path)) return;
    state = state._with(active: path);
  }

  /// Closes [path]. The tab that takes over is the one that moves into its
  /// place, so repeated closes walk the strip rather than jumping around.
  void close(String path) {
    final at = state.paths.indexOf(path);
    if (at < 0) return;
    final paths = [...state.paths]..removeAt(at);
    final active = state.active != path
        ? state.active
        : (paths.isEmpty ? null : paths[at.clamp(0, paths.length - 1)]);
    state = OpenFiles(
      paths: paths,
      active: active,
      dirty: {...state.dirty}..remove(path),
      gone: {...state.gone}..remove(path),
    );
  }

  void closeAll() => state = const OpenFiles();

  /// Forgets every unsaved mark, for editors that have gone away and taken
  /// their text with them. What is on disk is all that is left.
  void clearDirty() {
    if (state.dirty.isEmpty) return;
    state = state._with(dirty: const {});
  }

  void setDirty(String path, bool dirty) {
    if (state.isDirty(path) == dirty) return;
    final next = {...state.dirty};
    dirty ? next.add(path) : next.remove(path);
    state = state._with(dirty: next);
  }

  /// Follows a file moved on disk, so an open editor keeps pointing at the
  /// bytes it is showing rather than at a path that no longer exists.
  void rename(String from, String to) {
    final at = state.paths.indexOf(from);
    if (at < 0) return;
    final paths = [...state.paths];
    paths[at] = to;
    // The destination may itself have been open; one path, one tab.
    for (var i = paths.length - 1; i >= 0; i--) {
      if (i != at && paths[i] == to) paths.removeAt(i);
    }
    state = OpenFiles(
      paths: paths,
      active: state.active == from ? to : state.active,
      dirty: _moved(state.dirty, from, to),
      gone: _moved(state.gone, from, to)..remove(to),
    );
  }

  void markGone(String path) {
    if (!state.paths.contains(path) || state.isGone(path)) return;
    state = state._with(gone: {...state.gone, path});
  }

  void markPresent(String path) {
    if (!state.isGone(path)) return;
    state = state._with(gone: {...state.gone}..remove(path));
  }

  /// Reopens a persisted set on startup. Unsaved text is not part of it.
  void restore(List<String> paths, {String? active}) {
    state = OpenFiles(
      paths: List.of(paths),
      active: paths.contains(active) ? active : paths.firstOrNull,
    );
  }

  static Set<String> _moved(Set<String> set, String from, String to) {
    if (!set.contains(from)) return {...set};
    return {...set}
      ..remove(from)
      ..add(to);
  }
}

/// Keyed by repository path, so every repo tab carries its own editor tabs.
final openFilesProvider =
    StateNotifierProvider.family<OpenFilesNotifier, OpenFiles, String>(
      (ref, repoPath) => OpenFilesNotifier(),
    );
