import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/kv_store.dart';
import '../domain/path_key.dart';

part 'workspace.freezed.dart';

/// Which view a repo tab is showing: the commit history workspace, or the
/// project file browser and editor.
enum RepoViewMode {
  graph,
  files;

  /// Reads a persisted name, falling back to [graph] for anything missing or
  /// unrecognised — a payload written by an older or newer build must still
  /// open, just in the default view.
  static RepoViewMode parse(Object? name) {
    for (final m in RepoViewMode.values) {
      if (m.name == name) return m;
    }
    return RepoViewMode.graph;
  }
}

/// An open repository tab. [groupId] scopes it to a repo group (null = none).
@freezed
class RepoTab with _$RepoTab {
  const factory RepoTab({
    required int id,
    required String name,
    required String path,
    int? groupId,
    @Default(RepoViewMode.graph) RepoViewMode viewMode,
    // Files mode: the editor tabs this repo was left with. Paths only —
    // unsaved text is deliberately not persisted.
    @Default([]) List<String> openFiles,
    String? activeFile,
  }) = _RepoTab;
}

/// A named set of tabs with a colour, e.g. "Work" / "OSS".
@freezed
class RepoGroup with _$RepoGroup {
  const factory RepoGroup({
    required int id,
    required String name,
    required int colorValue,
  }) = _RepoGroup;
}

@freezed
class WorkspaceState with _$WorkspaceState {
  const WorkspaceState._();
  const factory WorkspaceState({
    @Default([]) List<RepoTab> tabs,
    int? activeTabId,
    @Default([]) List<RepoGroup> groups,
    // null = "All": no group filter applied.
    int? activeGroupId,
  }) = _WorkspaceState;

  /// A repo is "open" (workspace shown) only when the active tab is visible
  /// under the current group filter — an empty group shows Welcome instead,
  /// without discarding which tab was selected.
  bool get hasRepo => visibleTabs.any((t) => t.id == activeTabId);

  RepoTab? get activeTab {
    for (final t in tabs) {
      if (t.id == activeTabId) return t;
    }
    return null;
  }

  /// Tabs visible under the active group ("All" shows everything).
  List<RepoTab> get visibleTabs => activeGroupId == null
      ? tabs
      : [
          for (final t in tabs)
            if (t.groupId == activeGroupId) t,
        ];

  RepoGroup? groupById(int? id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// What a previous session left behind, restored at startup.
class WorkspaceSession {
  final List<
    ({
      String path,
      int? groupId,
      RepoViewMode viewMode,
      List<String> openFiles,
      String? activeFile,
    })
  >
  tabs;
  final List<RepoGroup> groups;
  final int? activeGroupId;
  const WorkspaceSession({
    this.tabs = const [],
    this.groups = const [],
    this.activeGroupId,
  });
}

class WorkspaceController extends StateNotifier<WorkspaceState> {
  final KeyValueStore? _store;

  /// Active profile whose workspace this holds. null = "no profile" (the
  /// legacy/global key), used before any profile exists.
  String? _profileId;
  WorkspaceController([this._store, this._profileId])
    : super(const WorkspaceState());

  static const _baseKey = 'openTabs';
  String get _storageKey =>
      _profileId == null ? _baseKey : '$_baseKey:$_profileId';
  int _nextId = 1;
  int _nextGroupId = 1;

  /// Group colour cycle (matches the branch palette accents).
  static const groupPalette = [
    0xFF4C5BF5,
    0xFF0E9F6E,
    0xFFB54708,
    0xFFD92D20,
    0xFF7A5AF8,
    0xFF0BA5EC,
    0xFFDD2590,
    0xFF3E4784,
  ];

  /// Restores the persisted session. Reads both the current object format and
  /// the legacy plain path list from earlier versions.
  static Future<WorkspaceSession> restoreSession(KeyValueStore store) =>
      _restore(store, _baseKey);

  /// Restores the session persisted for a specific profile.
  static Future<WorkspaceSession> restoreSessionFor(
    KeyValueStore store,
    String profileId,
  ) => _restore(store, '$_baseKey:$profileId');

  static Future<WorkspaceSession> _restore(
    KeyValueStore store,
    String key,
  ) async {
    final raw = await store.get(key);
    if (raw == null) return const WorkspaceSession();
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      // Legacy: ["path", ...]
      return WorkspaceSession(
        tabs: [
          for (final p in decoded)
            (
              path: p as String,
              groupId: null,
              viewMode: RepoViewMode.graph,
              openFiles: const <String>[],
              activeFile: null,
            ),
        ],
      );
    }
    final map = decoded as Map<String, dynamic>;
    return WorkspaceSession(
      tabs: [
        for (final t in (map['tabs'] as List? ?? const []))
          (
            path: (t as Map<String, dynamic>)['path'] as String,
            groupId: t['group'] as int?,
            viewMode: RepoViewMode.parse(t['view']),
            openFiles: [
              for (final f in (t['files'] as List? ?? const [])) f as String,
            ],
            activeFile: t['activeFile'] as String?,
          ),
      ],
      groups: [
        for (final g in (map['groups'] as List? ?? const []))
          RepoGroup(
            id: (g as Map<String, dynamic>)['id'] as int,
            name: g['name'] as String,
            colorValue: g['color'] as int,
          ),
      ],
      activeGroupId: map['activeGroup'] as int?,
    );
  }

  // Suppresses per-call persistence while a session is being restored, so the
  // intermediate (still group-less) state is never written to disk.
  bool _restoring = false;

  /// Applies a restored [session]: groups first, then tabs in order, then the
  /// active group. Persists exactly once, at the end.
  void applySession(WorkspaceSession session) {
    _restoring = true;
    try {
      for (final g in session.groups) {
        state = state.copyWith(groups: [...state.groups, g]);
        if (g.id >= _nextGroupId) _nextGroupId = g.id + 1;
      }
      for (final t in session.tabs) {
        final tab = openRepo(t.path);
        if (t.groupId != null) moveToGroup(tab.id, t.groupId);
        if (t.viewMode != RepoViewMode.graph) setViewMode(tab.id, t.viewMode);
        if (t.openFiles.isNotEmpty) {
          setOpenFiles(t.path, t.openFiles, t.activeFile);
        }
      }
      state = state.copyWith(activeGroupId: session.activeGroupId);
      _normalizeActive();
    } finally {
      // Never leave the guard stuck on: a throw mid-restore must not silence
      // all future persistence.
      _restoring = false;
    }
    _persist();
  }

  /// Switches this controller to [profileId]'s workspace: clears the current
  /// tabs/groups and applies the profile's restored [session]. Subsequent
  /// mutations persist under that profile's key.
  void useProfile(String profileId, WorkspaceSession session) {
    _profileId = profileId;
    _nextId = 1;
    _nextGroupId = 1;
    state = const WorkspaceState();
    applySession(session);
  }

  void _persist() {
    if (_restoring) return;
    _store?.put(
      _storageKey,
      jsonEncode({
        'tabs': [
          for (final t in state.tabs)
            {
              'path': t.path,
              'group': t.groupId,
              'view': t.viewMode.name,
              'files': t.openFiles,
              'activeFile': t.activeFile,
            },
        ],
        'groups': [
          for (final g in state.groups)
            {'id': g.id, 'name': g.name, 'color': g.colorValue},
        ],
        'activeGroup': state.activeGroupId,
      }),
    );
  }

  /// Keeps the active tab consistent with the group filter: if it is hidden
  /// while other tabs are visible, the first visible tab takes over. When the
  /// group is empty the selection is *preserved* (Welcome is shown via
  /// [WorkspaceState.hasRepo]), so round-tripping through an empty group never
  /// loses which repo was selected.
  void _normalizeActive() {
    final visible = state.visibleTabs;
    if (visible.isEmpty) return;
    if (!visible.any((t) => t.id == state.activeTabId)) {
      state = state.copyWith(activeTabId: visible.first.id);
    }
  }

  /// Opens [path] as a tab (or activates the existing one). Activating always
  /// jumps to the tab's group so it is visible; a new tab joins the active
  /// group. Returns the tab.
  RepoTab openRepo(String path, {String? name}) {
    for (final t in state.tabs) {
      // Normalised, not `==`: git reports resolved absolute paths while a tab
      // may carry the picker's spelling of the same directory, and the rest of
      // the app relies on one repository never being open in two tabs.
      if (samePath(t.path, path)) {
        final g = state.activeGroupId;
        // Opening a repo brings it into the active group (consistent with a
        // brand-new tab joining it). Under "All" (g == null) the tab's own
        // group is left untouched, and a tab already in g is only activated.
        state = state.copyWith(
          activeTabId: t.id,
          tabs: (g == null || t.groupId == g)
              ? state.tabs
              : [
                  for (final x in state.tabs)
                    if (x.id == t.id) x.copyWith(groupId: g) else x,
                ],
        );
        _persist();
        return t;
      }
    }
    final tab = RepoTab(
      id: _nextId++,
      name:
          name ?? path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last,
      path: path,
      groupId: state.activeGroupId,
    );
    state = state.copyWith(tabs: [...state.tabs, tab], activeTabId: tab.id);
    _persist();
    return tab;
  }

  void setActive(int id) => state = state.copyWith(activeTabId: id);

  /// Switches one tab between the history workspace and the file browser. The
  /// choice is per tab, so each open repo keeps the view it was left in.
  void setViewMode(int id, RepoViewMode mode) {
    state = state.copyWith(
      tabs: [
        for (final t in state.tabs)
          if (t.id == id) t.copyWith(viewMode: mode) else t,
      ],
    );
    _persist();
  }

  /// Records the editor tabs of the repository at [repoPath]. Keyed by path
  /// rather than tab id: the editors themselves are per repository, and the
  /// same repository is never open in two tabs.
  void setOpenFiles(String repoPath, List<String> files, String? active) {
    if (!state.tabs.any((t) => t.path == repoPath)) return;
    state = state.copyWith(
      tabs: [
        for (final t in state.tabs)
          if (t.path == repoPath)
            t.copyWith(openFiles: List.of(files), activeFile: active)
          else
            t,
      ],
    );
    _persist();
  }

  void closeTab(int id) {
    state = state.copyWith(tabs: state.tabs.where((t) => t.id != id).toList());
    _normalizeActive();
    _persist();
  }

  /// Closes every tab pointing at [path] — used when a worktree is removed
  /// from under one. Path comparison is normalised: the tab's spelling comes
  /// from a directory picker, the removed path from git.
  void closeTabsAt(String path) {
    final key = repoPathKey(path);
    final doomed = [
      for (final t in state.tabs)
        if (repoPathKey(t.path) == key) t.id,
    ];
    for (final id in doomed) {
      closeTab(id);
    }
  }

  /// Points every tab at [from] to [to] — a moved worktree is the same
  /// checkout at a new location, so its tab follows it rather than being left
  /// on a directory that no longer exists. Editor paths move with it, since
  /// they are absolute and all sit under the old root.
  void retargetTabs(String from, String to) {
    final key = repoPathKey(from);
    final leaf = to.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
    var changed = false;
    final tabs = [
      for (final t in state.tabs)
        if (repoPathKey(t.path) == key)
          () {
            changed = true;
            String move(String p) =>
                p.startsWith(t.path) ? '$to${p.substring(t.path.length)}' : p;
            return t.copyWith(
              path: to,
              name: leaf,
              openFiles: [for (final f in t.openFiles) move(f)],
              activeFile: t.activeFile == null ? null : move(t.activeFile!),
            );
          }()
        else
          t,
    ];
    if (!changed) return;
    state = state.copyWith(tabs: tabs);
    _persist();
  }

  void closeOthers(int id) {
    final keep = state.tabs.where((t) => t.id == id).toList();
    state = state.copyWith(
      tabs: keep,
      activeTabId: keep.isEmpty ? null : id,
      // Jump to the kept tab's group so it stays visible.
      activeGroupId: keep.isEmpty ? state.activeGroupId : keep.first.groupId,
    );
    _persist();
  }

  /// Moves the tab at [from] before the tab currently at [to] (indices into
  /// the full tab list) — drag-reorder.
  void reorderTab(int from, int to) {
    if (from < 0 || from >= state.tabs.length) return;
    final tabs = [...state.tabs];
    final tab = tabs.removeAt(from);
    // Removing shifts everything after [from] left by one, so a rightward
    // move must target one position earlier to land before the [to] tab.
    final at = from < to ? to - 1 : to;
    tabs.insert(at.clamp(0, tabs.length), tab);
    state = state.copyWith(tabs: tabs);
    _persist();
  }

  // --- Groups ---------------------------------------------------------------

  RepoGroup createGroup(String name) {
    final g = RepoGroup(
      id: _nextGroupId++,
      name: name,
      colorValue: groupPalette[(state.groups.length) % groupPalette.length],
    );
    state = state.copyWith(groups: [...state.groups, g]);
    _persist();
    return g;
  }

  void renameGroup(int id, String name) {
    state = state.copyWith(
      groups: [
        for (final g in state.groups)
          if (g.id == id) g.copyWith(name: name) else g,
      ],
    );
    _persist();
  }

  /// Deletes a group; its tabs stay open but become ungrouped.
  void deleteGroup(int id) {
    state = state.copyWith(
      groups: state.groups.where((g) => g.id != id).toList(),
      tabs: [
        for (final t in state.tabs)
          if (t.groupId == id) t.copyWith(groupId: null) else t,
      ],
      activeGroupId: state.activeGroupId == id ? null : state.activeGroupId,
    );
    _persist();
  }

  void moveToGroup(int tabId, int? groupId) {
    state = state.copyWith(
      tabs: [
        for (final t in state.tabs)
          if (t.id == tabId) t.copyWith(groupId: groupId) else t,
      ],
    );
    // Moving the active tab out of the active group hides it → re-normalize.
    if (!_restoring) _normalizeActive();
    _persist();
  }

  /// Switches the active group, keeping the active tab consistent with the
  /// filter — the first visible tab activates, or none when the group is empty.
  void setActiveGroup(int? groupId) {
    state = state.copyWith(activeGroupId: groupId);
    _normalizeActive();
    _persist();
  }
}

final workspaceProvider =
    StateNotifierProvider<WorkspaceController, WorkspaceState>(
      (ref) => WorkspaceController(),
    );
