import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/app_database.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/recents.dart';
import 'package:mergelio/state/settings.dart';

/// The SQLite-backed persistence layer, run against an in-memory database so
/// the real drift queries execute without touching the user's data file.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('AppDatabase key/value table', () {
    test('a key never written reads as null', () async {
      expect(await db.getValue('missing'), isNull);
    });

    test('a written value reads back', () async {
      await db.putValue('k', 'v1');
      expect(await db.getValue('k'), 'v1');
    });

    test('writing an existing key replaces its value', () async {
      await db.putValue('k', 'v1');
      await db.putValue('k', 'v2');
      expect(await db.getValue('k'), 'v2');
      expect(await db.select(db.keyValue).get(), hasLength(1));
    });

    test('keys are independent', () async {
      await db.putValue('a', '1');
      await db.putValue('b', '2');
      expect(await db.getValue('a'), '1');
      expect(await db.getValue('b'), '2');
    });
  });

  group('DriftKeyValueStore', () {
    test('reads and writes through the database', () async {
      final store = DriftKeyValueStore(db);
      expect(await store.get('profiles'), isNull);
      await store.put('profiles', '{"x":1}');
      expect(await store.get('profiles'), '{"x":1}');
      expect(await db.getValue('profiles'), '{"x":1}');
    });
  });

  group('InMemoryKeyValueStore', () {
    test('holds values per key and overwrites', () async {
      final store = InMemoryKeyValueStore();
      expect(await store.get('k'), isNull);
      await store.put('k', 'a');
      await store.put('k', 'b');
      expect(await store.get('k'), 'b');
    });
  });

  group('DriftSettingsRepository', () {
    test('defaults when nothing was saved', () async {
      final repo = DriftSettingsRepository(db);
      final s = await repo.load();
      expect(s.toJson(), const AppSettings().toJson());
    });

    test('a saved value loads back', () async {
      final repo = DriftSettingsRepository(db);
      final saved = const AppSettings().copyWith(
        restoreTabs: !const AppSettings().restoreTabs,
        editorCommand: 'code -w',
      );
      await repo.save(saved);

      final loaded = await DriftSettingsRepository(db).load();
      expect(loaded.restoreTabs, saved.restoreTabs);
      expect(loaded.editorCommand, 'code -w');
    });

    test(
      'an unreadable blob is kept under a backup key and defaults load',
      () async {
        await db.putValue('settings', '{not json');
        final repo = DriftSettingsRepository(db);

        final s = await repo.load();

        expect(s.toJson(), const AppSettings().toJson());
        expect(await db.getValue('settings.corrupt'), '{not json');
        // The original is left in place, not overwritten by the load.
        expect(await db.getValue('settings'), '{not json');
      },
    );

    test('a blob of the wrong shape is backed up too', () async {
      await db.putValue('settings', '[1, 2, 3]');
      final s = await DriftSettingsRepository(db).load();
      expect(s.toJson(), const AppSettings().toJson());
      expect(await db.getValue('settings.corrupt'), '[1, 2, 3]');
    });

    test('a readable blob leaves no backup behind', () async {
      final repo = DriftSettingsRepository(db);
      await repo.save(const AppSettings());
      await repo.load();
      expect(await db.getValue('settings.corrupt'), isNull);
    });
  });

  group('InMemorySettingsRepository', () {
    test('starts from the given value and keeps what is saved', () async {
      final start = const AppSettings().copyWith(editorCommand: 'vim');
      final repo = InMemorySettingsRepository(start);
      expect((await repo.load()).editorCommand, 'vim');
      await repo.save(start.copyWith(editorCommand: 'nano'));
      expect((await repo.load()).editorCommand, 'nano');
    });

    test('defaults with no starting value', () async {
      final repo = InMemorySettingsRepository();
      expect((await repo.load()).toJson(), const AppSettings().toJson());
    });
  });

  group('RecentsRepository', () {
    test('empty when nothing was saved', () async {
      expect(await RecentsRepository(db).load(), isEmpty);
    });

    test('round-trips the list in order, pinned flag included', () async {
      final repo = RecentsRepository(db);
      await repo.save(const [
        RecentRepo(name: 'a', path: '/a', pinned: true),
        RecentRepo(name: 'b', path: '/b'),
      ]);
      final back = await RecentsRepository(db).load();
      expect(back, const [
        RecentRepo(name: 'a', path: '/a', pinned: true),
        RecentRepo(name: 'b', path: '/b'),
      ]);
    });

    test('an unreadable list loads as empty', () async {
      await db.putValue('recents', 'garbage');
      expect(await RecentsRepository(db).load(), isEmpty);
    });

    test('a list with a malformed entry loads as empty', () async {
      await db.putValue(
        'recents',
        jsonEncode([
          {'name': 'ok', 'path': '/ok'},
          {'name': 1},
        ]),
      );
      expect(await RecentsRepository(db).load(), isEmpty);
    });
  });
}
