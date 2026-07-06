import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../state/settings.dart';
import 'app_database.dart';

/// Storage boundary for [AppSettings]. An interface so tests and previews can
/// use [InMemorySettingsRepository] without a real database.
abstract class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

/// SQLite-backed implementation. A corrupt blob is preserved under a backup
/// key (never silently destroyed) before defaults are returned.
class DriftSettingsRepository implements SettingsRepository {
  final AppDatabase db;
  DriftSettingsRepository(this.db);

  static const _key = 'settings';
  static const _backupKey = 'settings.corrupt';

  @override
  Future<AppSettings> load() async {
    final raw = await db.getValue(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // Keep the unreadable blob for recovery/diagnostics instead of letting
      // the next save overwrite it.
      debugPrint('settings: corrupt blob backed up ($e)');
      await db.putValue(_backupKey, raw);
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) =>
      db.putValue(_key, jsonEncode(settings.toJson()));
}

/// Non-persistent implementation for tests.
class InMemorySettingsRepository implements SettingsRepository {
  AppSettings _value;
  InMemorySettingsRepository([this._value = const AppSettings()]);

  @override
  Future<AppSettings> load() async => _value;

  @override
  Future<void> save(AppSettings settings) async => _value = settings;
}
