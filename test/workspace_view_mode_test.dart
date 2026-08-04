import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  test('a new tab opens in graph mode', () {
    final c = WorkspaceController();
    final tab = c.openRepo('/repos/alpha');
    expect(tab.viewMode, RepoViewMode.graph);
  });

  test('setViewMode changes only the target tab', () {
    final c = WorkspaceController();
    final a = c.openRepo('/a');
    final b = c.openRepo('/b');

    c.setViewMode(a.id, RepoViewMode.files);

    expect(
      c.state.tabs.firstWhere((t) => t.id == a.id).viewMode,
      RepoViewMode.files,
    );
    expect(
      c.state.tabs.firstWhere((t) => t.id == b.id).viewMode,
      RepoViewMode.graph,
    );
  });

  test('view mode round-trips through persistence', () async {
    final store = InMemoryKeyValueStore();
    final c = WorkspaceController(store);
    final a = c.openRepo('/a');
    c.openRepo('/b');
    c.setViewMode(a.id, RepoViewMode.files);

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.map((t) => t.viewMode), [
      RepoViewMode.files,
      RepoViewMode.graph,
    ]);

    // Applying the session rebuilds tabs carrying their mode.
    final c2 = WorkspaceController(InMemoryKeyValueStore())
      ..applySession(session);
    expect(c2.state.tabs.map((t) => t.viewMode), [
      RepoViewMode.files,
      RepoViewMode.graph,
    ]);
  });

  test('a payload saved before view modes existed restores as graph', () async {
    final store = InMemoryKeyValueStore();
    await store.put(
      'openTabs',
      jsonEncode({
        'tabs': [
          {'path': '/old/one', 'group': null},
        ],
        'groups': [],
        'activeGroup': null,
      }),
    );

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.single.viewMode, RepoViewMode.graph);
  });

  test('the legacy plain path list restores as graph', () async {
    final store = InMemoryKeyValueStore();
    await store.put('openTabs', jsonEncode(['/old/one']));

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.single.viewMode, RepoViewMode.graph);
  });

  test('an unknown persisted mode falls back to graph', () async {
    final store = InMemoryKeyValueStore();
    await store.put(
      'openTabs',
      jsonEncode({
        'tabs': [
          {'path': '/a', 'group': null, 'view': 'hologram'},
        ],
        'groups': [],
        'activeGroup': null,
      }),
    );

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.single.viewMode, RepoViewMode.graph);
  });
}
