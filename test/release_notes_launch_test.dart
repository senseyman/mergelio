import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/release_notes.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:pub_semver/pub_semver.dart';

Version v(String s) => Version.parse(s);

void main() {
  final available = [v('1.8.0'), v('1.9.0'), v('1.10.0')];

  group('releaseNotesOnLaunch', () {
    late InMemoryKeyValueStore store;
    setUp(() => store = InMemoryKeyValueStore());

    Future<List<Version>> launch(String current) => releaseNotesOnLaunch(
      store: store,
      current: v(current),
      available: available,
    );

    test('fresh install shows nothing and records the version', () async {
      expect(await launch('1.9.0'), isEmpty);
      expect(await store.get(releaseNotesSeenKey), '1.9.0');
    });

    test('upgrade shows notes once', () async {
      await store.put(releaseNotesSeenKey, '1.8.0');
      expect(await launch('1.9.0'), [v('1.9.0')]);
      expect(await store.get(releaseNotesSeenKey), '1.9.0');
      expect(await launch('1.9.0'), isEmpty);
    });

    test('downgrade lowers the marker so a re-upgrade shows again', () async {
      await store.put(releaseNotesSeenKey, '1.10.0');
      expect(await launch('1.9.0'), isEmpty);
      expect(await store.get(releaseNotesSeenKey), '1.9.0');
      expect(await launch('1.10.0'), [v('1.10.0')]);
    });

    test('an unreadable marker counts as a fresh install', () async {
      await store.put(releaseNotesSeenKey, 'not-a-version');
      expect(await launch('1.9.0'), isEmpty);
      expect(await store.get(releaseNotesSeenKey), '1.9.0');
    });

    test('a build suffix on the marker is ignored', () async {
      await store.put(releaseNotesSeenKey, '1.8.0+25');
      expect(await launch('1.9.0'), [v('1.9.0')]);
    });
  });

  group('releaseNotesLaunchProvider', () {
    test('combines version, assets and store', () async {
      final store = InMemoryKeyValueStore();
      await store.put(releaseNotesSeenKey, '1.8.0');
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(store),
          currentReleaseProvider.overrideWith((ref) async => v('1.10.0')),
          releaseNotesAssetsProvider.overrideWith(
            (ref) async => {
              v('1.9.0'): {'en'},
              v('1.10.0'): {'en', 'uk'},
            },
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(releaseNotesLaunchProvider.future), [
        v('1.10.0'),
        v('1.9.0'),
      ]);
    });

    test('any failure means no tab rather than a broken launch', () async {
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          currentReleaseProvider.overrideWith(
            (ref) async => throw StateError('no package info'),
          ),
          releaseNotesAssetsProvider.overrideWith((ref) async => {}),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(releaseNotesLaunchProvider.future), isEmpty);
    });
  });

  group('releaseNotesStartupProvider', () {
    Future<WorkspaceState> start(List<Version> launch) async {
      final c = ProviderContainer(
        overrides: [
          releaseNotesLaunchProvider.overrideWith((ref) async => launch),
        ],
      );
      addTearDown(c.dispose);
      await c.read(releaseNotesStartupProvider.future);
      return c.read(workspaceProvider);
    }

    test('opens the tab with the launch notes', () async {
      final ws = await start([v('1.9.0')]);
      expect(ws.releaseNotes, [v('1.9.0')]);
      expect(ws.showReleaseNotes, isTrue);
    });

    test('leaves the workspace alone when there are none', () async {
      final ws = await start(const []);
      expect(ws.releaseNotes, isNull);
    });
  });
}
