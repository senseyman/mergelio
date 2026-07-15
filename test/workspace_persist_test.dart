import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  test('open tabs persist and restore in order', () async {
    final store = InMemoryKeyValueStore();
    final c = WorkspaceController(store);

    c.openRepo('/repos/alpha');
    c.openRepo('/repos/beta');
    c.openRepo('/repos/gamma');

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.map((t) => t.path), [
      '/repos/alpha',
      '/repos/beta',
      '/repos/gamma',
    ]);
  });

  test('closing a tab updates the persisted set', () async {
    final store = InMemoryKeyValueStore();
    final c = WorkspaceController(store);
    final a = c.openRepo('/a');
    c.openRepo('/b');
    c.closeTab(a.id);

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.map((t) => t.path), ['/b']);
  });

  test('restoreSession is empty when nothing was saved', () async {
    final session = await WorkspaceController.restoreSession(
      InMemoryKeyValueStore(),
    );
    expect(session.tabs, isEmpty);
    expect(session.groups, isEmpty);
  });

  test('legacy plain path-list format still restores', () async {
    final store = InMemoryKeyValueStore();
    await store.put('openTabs', jsonEncode(['/old/one', '/old/two']));

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.map((t) => t.path), ['/old/one', '/old/two']);
    expect(session.groups, isEmpty);
  });

  test('groups, membership and active group round-trip', () async {
    final store = InMemoryKeyValueStore();
    final c = WorkspaceController(store);
    final work = c.createGroup('Work');
    final oss = c.createGroup('OSS');
    final a = c.openRepo('/w/a');
    final b = c.openRepo('/o/b');
    c.moveToGroup(a.id, work.id);
    c.moveToGroup(b.id, oss.id);
    c.setActiveGroup(oss.id);

    final session = await WorkspaceController.restoreSession(store);
    expect(session.groups.map((g) => g.name), ['Work', 'OSS']);
    expect(session.activeGroupId, oss.id);

    // Re-apply into a fresh controller: filtering works after restart.
    final c2 = WorkspaceController(InMemoryKeyValueStore())
      ..applySession(session);
    expect(c2.state.visibleTabs.map((t) => t.path), ['/o/b']);
  });

  test('switching group activates the first visible tab', () {
    final c = WorkspaceController();
    final g = c.createGroup('G');
    final a = c.openRepo('/a'); // ungrouped
    final b = c.openRepo('/b');
    c.moveToGroup(b.id, g.id);
    c.setActive(a.id);

    c.setActiveGroup(g.id);
    expect(c.state.activeTabId, b.id);
    expect(c.state.visibleTabs.map((t) => t.id), [b.id]);

    // "All" shows everything again.
    c.setActiveGroup(null);
    expect(c.state.visibleTabs.length, 2);
  });

  test('empty group hides the workspace but preserves the selection', () {
    final c = WorkspaceController();
    final a = c.openRepo('/a'); // ungrouped, active
    c.openRepo('/b');
    c.setActive(a.id);
    final g = c.createGroup('Empty');

    c.setActiveGroup(g.id);
    expect(c.state.visibleTabs, isEmpty);
    // Welcome is shown (no visible active tab)...
    expect(c.state.hasRepo, isFalse);
    // ...but the selection is not discarded.
    expect(c.state.activeTabId, a.id);

    // Round-trip back to "All" restores the same selected repo.
    c.setActiveGroup(null);
    expect(c.state.activeTabId, a.id);
    expect(c.state.hasRepo, isTrue);
  });

  test('re-opening a visible tab does not collapse the All filter', () {
    final c = WorkspaceController();
    final g = c.createGroup('G');
    c.openRepo('/a'); // ungrouped
    final b = c.openRepo('/b');
    c.moveToGroup(b.id, g.id); // /b in group G, /a ungrouped
    c.setActiveGroup(null); // All

    // Re-open /a (visible under All) — filter must stay All.
    c.openRepo('/a');
    expect(c.state.activeGroupId, isNull);
    expect(c.state.visibleTabs.length, 2);
  });

  test('opening a repo brings its tab into the active group', () {
    final c = WorkspaceController();
    final work = c.createGroup('Work');
    final oss = c.createGroup('OSS');
    final a = c.openRepo('/a');
    c.moveToGroup(a.id, work.id);
    final b = c.openRepo('/b');
    c.moveToGroup(b.id, oss.id);
    c.setActiveGroup(work.id);

    // Re-opening /b (was in OSS) while Work is active moves it into Work so it
    // is visible where the user is working — the filter never jumps away.
    c.openRepo('/b');
    expect(c.state.activeTabId, b.id);
    expect(c.state.activeGroupId, work.id);
    expect(c.state.tabs.firstWhere((t) => t.id == b.id).groupId, work.id);
    expect(c.state.visibleTabs.map((t) => t.id), containsAll([a.id, b.id]));
  });

  test('opening a NEW repo in a fresh empty group lands it in that group', () {
    final c = WorkspaceController();
    c.openRepo('/a'); // ungrouped
    final g = c.createGroup('New');
    c.setActiveGroup(g.id); // empty group active

    final b = c.openRepo('/b'); // open a repo "in" the new group
    expect(c.state.activeGroupId, g.id);
    expect(c.state.tabs.firstWhere((t) => t.id == b.id).groupId, g.id);
    expect(c.state.visibleTabs.map((t) => t.path), ['/b']);
  });

  test('restored active tab is never left outside its group', () async {
    final store = InMemoryKeyValueStore();
    final c = WorkspaceController(store);
    final work = c.createGroup('Work');
    final oss = c.createGroup('OSS');
    final a = c.openRepo('/a');
    c.moveToGroup(a.id, work.id);
    final b = c.openRepo('/b');
    c.moveToGroup(b.id, oss.id);
    c.setActiveGroup(work.id);

    // Restore into a fresh controller.
    final session = await WorkspaceController.restoreSession(store);
    final c2 = WorkspaceController(InMemoryKeyValueStore())
      ..applySession(session);
    // Active group Work → active tab must be a Work tab (/a), not the
    // last-opened /b.
    expect(c2.state.activeGroupId, work.id);
    expect(c2.state.activeTab?.path, '/a');
    // And the restored active-group survives a second round-trip.
    final again = await WorkspaceController.restoreSession(store);
    expect(again.activeGroupId, work.id);
  });

  test('deleting a group ungroups its tabs and resets the filter', () {
    final c = WorkspaceController();
    final g = c.createGroup('Temp');
    final a = c.openRepo('/a');
    c.moveToGroup(a.id, g.id);
    c.setActiveGroup(g.id);

    c.deleteGroup(g.id);
    expect(c.state.groups, isEmpty);
    expect(c.state.activeGroupId, isNull);
    expect(c.state.tabs.single.groupId, isNull);
  });

  test('reorderTab moves a tab within the strip (both directions)', () {
    final c = WorkspaceController();
    c.openRepo('/a');
    c.openRepo('/b');
    c.openRepo('/c');

    // Rightward: drop /a before /c → it lands between /b and /c.
    c.reorderTab(0, 2);
    expect(c.state.tabs.map((t) => t.path), ['/b', '/a', '/c']);

    // Leftward: drop /c before /b (index 0).
    c.reorderTab(2, 0);
    expect(c.state.tabs.map((t) => t.path), ['/c', '/b', '/a']);
  });
}
