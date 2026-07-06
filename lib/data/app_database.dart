import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Simple key/value table backing settings and other small persisted state.
/// Larger domain data gets dedicated tables in later stages.
class KeyValue extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [KeyValue])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  Future<String?> getValue(String key) async {
    final row = await (select(
      keyValue,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> putValue(String key, String value) => into(
    keyValue,
  ).insertOnConflictUpdate(KeyValueCompanion.insert(key: key, value: value));

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'mergelio.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
