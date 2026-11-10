import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kv_store.dart';
import 'operation_journal.dart';
import 'settings.dart';
import 'settings_controller.dart';

/// The kinds of event Mergelio can raise a desktop notification for.
enum NotifyEvent { longOps, ci, pullRequests }

/// A repo's say on one [NotifyEvent]: follow the global default, or force it.
enum NotifyOverride { inherit, on, off }

/// Whether [e] notifies for a repo whose override is [o]. The master switch
/// wins over everything, a repo's `on` / `off` wins over the global default,
/// and `inherit` follows the global default.
bool effectiveNotify(AppSettings s, NotifyEvent e, NotifyOverride o) {
  if (!s.notificationsEnabled) return false;
  return switch (o) {
    NotifyOverride.on => true,
    NotifyOverride.off => false,
    NotifyOverride.inherit => switch (e) {
      NotifyEvent.longOps => s.notifyLongOps,
      NotifyEvent.ci => s.notifyCi,
      NotifyEvent.pullRequests => s.notifyPullRequests,
    },
  };
}

/// One repo's notification overrides. An event with no entry inherits.
class RepoNotifyPrefs {
  final Map<NotifyEvent, NotifyOverride> overrides;
  const RepoNotifyPrefs([this.overrides = const {}]);

  NotifyOverride of(NotifyEvent e) => overrides[e] ?? NotifyOverride.inherit;

  RepoNotifyPrefs copyWith(NotifyEvent e, NotifyOverride o) {
    final next = {...overrides};
    if (o == NotifyOverride.inherit) {
      next.remove(e);
    } else {
      next[e] = o;
    }
    return RepoNotifyPrefs(next);
  }

  String toJson() => jsonEncode({
    for (final e in NotifyEvent.values)
      if (of(e) != NotifyOverride.inherit) e.name: of(e).name,
  });

  /// Reads stored prefs; anything absent, unreadable or unrecognised
  /// inherits.
  static RepoNotifyPrefs fromJson(String? raw) {
    if (raw == null) return const RepoNotifyPrefs();
    final Object? j;
    try {
      j = jsonDecode(raw);
    } on FormatException {
      return const RepoNotifyPrefs();
    }
    if (j is! Map) return const RepoNotifyPrefs();
    final out = <NotifyEvent, NotifyOverride>{};
    for (final e in NotifyEvent.values) {
      final v = j[e.name];
      if (v == 'on') out[e] = NotifyOverride.on;
      if (v == 'off') out[e] = NotifyOverride.off;
    }
    return RepoNotifyPrefs(out);
  }
}

/// Holds one repo's overrides, loaded from the key-value store on creation
/// and written back on every change.
class RepoNotifyPrefsController extends StateNotifier<RepoNotifyPrefs> {
  final KeyValueStore _kv;
  final String _key;
  late final Future<void> _loaded;
  bool _loadOk = false;

  RepoNotifyPrefsController(this._kv, String repo)
    : _key = 'notifications:$repo',
      super(const RepoNotifyPrefs()) {
    _loaded = _load();
  }

  /// Completes once the stored prefs have been read (or the read failed).
  Future<void> get loaded => _loaded;

  Future<void> _load() async {
    try {
      final loaded = RepoNotifyPrefs.fromJson(await _kv.get(_key));
      _loadOk = true;
      if (mounted) state = loaded;
    } catch (e) {
      debugPrint('notification prefs load failed: $e');
    }
  }

  /// Changes one override and saves. Waits for the stored prefs first, so a
  /// change made right after creation builds on them instead of replacing
  /// them. If the stored prefs could not be read, the read is retried; when
  /// it still fails the change is kept in memory only, so a transient read
  /// failure never overwrites what is stored.
  Future<void> set(NotifyEvent e, NotifyOverride o) async {
    await _loaded;
    if (!mounted) return;
    if (!_loadOk) await _load();
    if (!mounted) return;
    state = state.copyWith(e, o);
    if (!_loadOk) return;
    await _kv.put(_key, state.toJson());
  }
}

final repoNotifyPrefsProvider =
    StateNotifierProvider.family<
      RepoNotifyPrefsController,
      RepoNotifyPrefs,
      String
    >(
      (ref, path) =>
          RepoNotifyPrefsController(ref.watch(kvStoreProvider), path),
    );

/// Whether [event] notifies for the repo at the given path, combining the
/// global settings with the repo's override. With the master switch off the
/// repo's override is never loaded, so nothing reads the store per open tab.
final notifyEnabledProvider =
    Provider.family<bool, (String repoPath, NotifyEvent event)>((ref, key) {
      final s = ref.watch(settingsProvider);
      if (!s.notificationsEnabled) return false;
      final o = ref.watch(repoNotifyPrefsProvider(key.$1)).of(key.$2);
      return effectiveNotify(s, key.$2, o);
    });
