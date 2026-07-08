import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/kv_store.dart';

part 'workspace.freezed.dart';

/// An open repository tab.
@freezed
class RepoTab with _$RepoTab {
  const factory RepoTab({
    required int id,
    required String name,
    required String path,
  }) = _RepoTab;
}

@freezed
class WorkspaceState with _$WorkspaceState {
  const WorkspaceState._();
  const factory WorkspaceState({
    @Default([]) List<RepoTab> tabs,
    int? activeTabId,
  }) = _WorkspaceState;

  bool get hasRepo => tabs.isNotEmpty && activeTabId != null;

  RepoTab? get activeTab {
    for (final t in tabs) {
      if (t.id == activeTabId) return t;
    }
    return null;
  }
}

class WorkspaceController extends StateNotifier<WorkspaceState> {
  final KeyValueStore? _store;
  WorkspaceController([this._store]) : super(const WorkspaceState());

  static const _key = 'openTabs';
  int _nextId = 1;

  /// Open tab paths persisted from a previous session, in order.
  static Future<List<String>> restorePaths(KeyValueStore store) async {
    final raw = await store.get(_key);
    if (raw == null) return const [];
    return [for (final p in jsonDecode(raw) as List) p as String];
  }

  void _persist() =>
      _store?.put(_key, jsonEncode([for (final t in state.tabs) t.path]));

  /// Opens [path] as a tab (or activates the existing one). Returns the tab.
  RepoTab openRepo(String path, {String? name}) {
    for (final t in state.tabs) {
      if (t.path == path) {
        state = state.copyWith(activeTabId: t.id);
        return t;
      }
    }
    final tab = RepoTab(
      id: _nextId++,
      name:
          name ?? path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last,
      path: path,
    );
    state = state.copyWith(tabs: [...state.tabs, tab], activeTabId: tab.id);
    _persist();
    return tab;
  }

  void setActive(int id) => state = state.copyWith(activeTabId: id);

  void closeTab(int id) {
    final tabs = state.tabs.where((t) => t.id != id).toList();
    final active = state.activeTabId == id
        ? (tabs.isEmpty ? null : tabs.first.id)
        : state.activeTabId;
    state = state.copyWith(tabs: tabs, activeTabId: active);
    _persist();
  }

  void closeOthers(int id) {
    final keep = state.tabs.where((t) => t.id == id).toList();
    state = state.copyWith(tabs: keep, activeTabId: keep.isEmpty ? null : id);
    _persist();
  }
}

final workspaceProvider =
    StateNotifierProvider<WorkspaceController, WorkspaceState>(
      (ref) => WorkspaceController(),
    );
