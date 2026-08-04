// Editor tabs survive a restart: which files were open is persisted with the
// repo tab, while the text in them is not.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/open_files_sync.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  test('a new tab has nothing open', () {
    final c = WorkspaceController();
    expect(c.openRepo('/a').openFiles, isEmpty);
  });

  test('open files round-trip through persistence', () async {
    final store = InMemoryKeyValueStore();
    final c = WorkspaceController(store);
    final a = c.openRepo('/a');

    c.setOpenFiles('/a', const ['lib/main.dart', 'README.md'], 'README.md');

    expect(c.state.tabs.firstWhere((t) => t.id == a.id).openFiles, [
      'lib/main.dart',
      'README.md',
    ]);

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.single.openFiles, ['lib/main.dart', 'README.md']);
    expect(session.tabs.single.activeFile, 'README.md');

    final c2 = WorkspaceController(InMemoryKeyValueStore())
      ..applySession(session);
    expect(c2.state.tabs.single.openFiles, ['lib/main.dart', 'README.md']);
    expect(c2.state.tabs.single.activeFile, 'README.md');
  });

  test('a payload saved before editor tabs existed restores empty', () async {
    final store = InMemoryKeyValueStore();
    await store.put(
      'openTabs',
      jsonEncode({
        'tabs': [
          {'path': '/old', 'group': null},
        ],
        'groups': [],
        'activeGroup': null,
      }),
    );

    final session = await WorkspaceController.restoreSession(store);
    expect(session.tabs.single.openFiles, isEmpty);
    expect(session.tabs.single.activeFile, isNull);
  });

  test('every open tab restores its own set of files', () async {
    final workspace = WorkspaceController()..openRepo('/a');
    workspace
      ..setOpenFiles('/a', const ['a.txt'], 'a.txt')
      ..openRepo('/b')
      ..setOpenFiles('/b', const ['b.txt'], 'b.txt');
    final c = ProviderContainer(
      overrides: [workspaceProvider.overrideWith((ref) => workspace)],
    );
    addTearDown(c.dispose);

    c.read(openFilesSyncProvider);
    // Wiring lands a microtask after the provider is built.
    await Future<void>.delayed(Duration.zero);

    expect(c.read(openFilesProvider('/a')).paths, ['a.txt']);
    expect(c.read(openFilesProvider('/a')).active, 'a.txt');
    expect(c.read(openFilesProvider('/b')).paths, ['b.txt']);
  });

  test('a tab opened later restores its files too', () async {
    final workspace = WorkspaceController();
    final c = ProviderContainer(
      overrides: [workspaceProvider.overrideWith((ref) => workspace)],
    );
    addTearDown(c.dispose);
    c.read(openFilesSyncProvider);
    // Wiring lands a microtask after the provider is built.
    await Future<void>.delayed(Duration.zero);

    workspace.openRepo('/late');
    workspace.setOpenFiles('/late', const ['x.txt'], 'x.txt');

    expect(c.read(openFilesProvider('/late')).paths, ['x.txt']);
  });

  test('opening a file writes it back to the repo tab', () async {
    final workspace = WorkspaceController()..openRepo('/a');
    final c = ProviderContainer(
      overrides: [workspaceProvider.overrideWith((ref) => workspace)],
    );
    addTearDown(c.dispose);
    c.read(openFilesSyncProvider);
    // Wiring lands a microtask after the provider is built.
    await Future<void>.delayed(Duration.zero);

    c.read(openFilesProvider('/a').notifier).open('lib/main.dart');

    expect(workspace.state.tabs.single.openFiles, ['lib/main.dart']);
    expect(workspace.state.tabs.single.activeFile, 'lib/main.dart');
  });

  test('unsaved text is never part of what is persisted', () async {
    final workspace = WorkspaceController()..openRepo('/a');
    final c = ProviderContainer(
      overrides: [workspaceProvider.overrideWith((ref) => workspace)],
    );
    addTearDown(c.dispose);
    c.read(openFilesSyncProvider);
    // Wiring lands a microtask after the provider is built.
    await Future<void>.delayed(Duration.zero);

    c.read(openFilesProvider('/a').notifier)
      ..open('a.txt')
      ..setDirty('a.txt', true);

    // The tab records the path; what the editor holds stays in memory.
    expect(workspace.state.tabs.single.openFiles, ['a.txt']);
  });
}
