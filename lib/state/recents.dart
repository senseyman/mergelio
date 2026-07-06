import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/app_database.dart';

part 'recents.freezed.dart';
part 'recents.g.dart';

/// A recently opened repository (pinnable, shown on the Welcome screen).
@freezed
class RecentRepo with _$RecentRepo {
  const factory RecentRepo({
    required String name,
    required String path,
    @Default(false) bool pinned,
  }) = _RecentRepo;

  factory RecentRepo.fromJson(Map<String, dynamic> json) =>
      _$RecentRepoFromJson(json);
}

/// Persists the recents list as a JSON array in the key/value store.
class RecentsRepository {
  final AppDatabase db;
  RecentsRepository(this.db);

  static const _key = 'recents';

  Future<List<RecentRepo>> load() async {
    final raw = await db.getValue(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => RecentRepo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('recents: unreadable list ignored ($e)');
      return const [];
    }
  }

  Future<void> save(List<RecentRepo> items) =>
      db.putValue(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
}

class RecentsController extends StateNotifier<List<RecentRepo>> {
  final RecentsRepository repo;
  static const _max = 12;

  RecentsController(this.repo, List<RecentRepo> initial) : super(initial);

  /// Adds (or refreshes) an entry at the top; pinned entries keep their flag.
  void add(String name, String path) {
    final existing = state.where((r) => r.path == path).firstOrNull;
    final entry =
        existing?.copyWith(name: name) ?? RecentRepo(name: name, path: path);
    final rest = state.where((r) => r.path != path).toList();
    _update([entry, ...rest].take(_max).toList());
  }

  void togglePin(String path) => _update([
    for (final r in state)
      if (r.path == path) r.copyWith(pinned: !r.pinned) else r,
  ]);

  void remove(String path) =>
      _update(state.where((r) => r.path != path).toList());

  void _update(List<RecentRepo> next) {
    // Pinned entries sort first, preserving relative order.
    final sorted = [
      ...next.where((r) => r.pinned),
      ...next.where((r) => !r.pinned),
    ];
    state = sorted;
    repo.save(sorted).catchError((Object e) {
      debugPrint('recents: save failed: $e');
    });
  }
}

/// Overridden in `main()` with the loaded list + repository.
final recentsProvider =
    StateNotifierProvider<RecentsController, List<RecentRepo>>(
      (ref) => throw UnimplementedError('recentsProvider must be overridden'),
    );
