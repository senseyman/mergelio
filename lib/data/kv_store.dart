import 'app_database.dart';

/// A small string key/value store used for JSON-encoded app state (profiles,
/// groups, session). Backed by the drift KV table in production.
abstract class KeyValueStore {
  Future<String?> get(String key);
  Future<void> put(String key, String value);
}

class DriftKeyValueStore implements KeyValueStore {
  final AppDatabase db;
  const DriftKeyValueStore(this.db);

  @override
  Future<String?> get(String key) => db.getValue(key);

  @override
  Future<void> put(String key, String value) => db.putValue(key, value);
}

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _map = {};

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<void> put(String key, String value) async => _map[key] = value;
}
