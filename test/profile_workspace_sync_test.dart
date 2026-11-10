import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/profile_workspace_sync.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/workspace.dart';

/// Switching the active profile swaps in that profile's saved workspace.
void main() {
  const work = Profile(
    id: 'work',
    label: 'Work',
    name: 'W',
    email: 'w@example.com',
    colorValue: 0xFF000000,
  );
  const home = Profile(
    id: 'home',
    label: 'Home',
    name: 'H',
    email: 'h@example.com',
    colorValue: 0xFF000000,
  );

  late InMemoryKeyValueStore store;
  late ProviderContainer c;

  setUp(() async {
    store = InMemoryKeyValueStore();
    // Each profile already has a workspace on disk.
    WorkspaceController(store, 'work').openRepo('/work/alpha');
    WorkspaceController(store, 'home').openRepo('/home/beta');
    await Future<void>.delayed(Duration.zero);

    c = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(store),
        profilesProvider.overrideWith(
          (ref) => ProfilesController(
            store,
            const ProfilesState(profiles: [work, home], activeId: 'work'),
          ),
        ),
        workspaceProvider.overrideWith(
          (ref) => WorkspaceController(store, 'work')..openRepo('/work/alpha'),
        ),
      ],
    );
    addTearDown(c.dispose);
    // Build the workspace now: built lazily, its opening write would land
    // in the middle of a test.
    c.read(workspaceProvider);
    c.read(profileWorkspaceSyncProvider);
  });

  List<String> tabs() => [
    for (final t in c.read(workspaceProvider).tabs) t.path,
  ];

  /// The switch restores the session asynchronously.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('switching profile loads that profile\'s workspace', () async {
    c.read(profilesProvider.notifier).setActive('home');
    await settle();
    expect(tabs(), ['/home/beta']);
  });

  test('switching back restores the first workspace', () async {
    final profiles = c.read(profilesProvider.notifier);
    profiles.setActive('home');
    await settle();
    profiles.setActive('work');
    await settle();
    expect(tabs(), ['/work/alpha']);
  });

  test('re-selecting the active profile leaves the workspace alone', () async {
    c.read(workspaceProvider.notifier).openRepo('/work/unsaved-extra');
    c.read(profilesProvider.notifier).setActive('work');
    await settle();
    expect(tabs(), ['/work/alpha', '/work/unsaved-extra']);
  });

  test('removing the last profile does not clear the workspace', () async {
    final profiles = c.read(profilesProvider.notifier);
    profiles.remove('home');
    profiles.remove('work');
    await settle();
    expect(c.read(profilesProvider).activeId, isNull);
    expect(tabs(), ['/work/alpha']);
  });

  test('the profile already loaded is not reloaded when it comes back', () async {
    final profiles = c.read(profilesProvider.notifier);
    profiles.remove('home');
    profiles.remove('work');
    await settle();
    // Something else rewrote the saved copy meanwhile; a reload would show it.
    await store.put('openTabs:work', '["/elsewhere"]');

    profiles.add(work); // the first profile added becomes active again
    await settle();
    expect(c.read(profilesProvider).activeId, 'work');
    expect(tabs(), ['/work/alpha']);
  });

  test('an unreadable saved workspace keeps the current one', () async {
    await store.put('openTabs:home', '{broken');
    c.read(profilesProvider.notifier).setActive('home');
    await settle();
    expect(tabs(), ['/work/alpha']);
  });
}
