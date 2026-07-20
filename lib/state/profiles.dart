import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kv_store.dart';

/// A commit identity: name/email plus a colour. SSH keys/tokens live in the
/// system keychain (added with the secure-storage integration), never here.
class Profile {
  final String id;

  /// Display name of the profile itself (e.g. "Work", "Personal"). Distinct
  /// from [name], the git author identity.
  final String label;
  final String name;
  final String email;
  final int colorValue;
  const Profile({
    required this.id,
    required this.label,
    required this.name,
    required this.email,
    required this.colorValue,
  });

  Profile copyWith({
    String? label,
    String? name,
    String? email,
    int? colorValue,
  }) => Profile(
    id: id,
    label: label ?? this.label,
    name: name ?? this.name,
    email: email ?? this.email,
    colorValue: colorValue ?? this.colorValue,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'name': name,
    'email': email,
    'color': colorValue,
  };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    // Legacy profiles had no label — fall back to the git name.
    label: (j['label'] ?? j['name']) as String,
    name: j['name'] as String,
    email: j['email'] as String,
    colorValue: j['color'] as int,
  );
}

class ProfilesState {
  final List<Profile> profiles;
  final String? activeId;
  const ProfilesState({this.profiles = const [], this.activeId});

  Profile? get active {
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'profiles': [for (final p in profiles) p.toJson()],
    'activeId': activeId,
  };

  factory ProfilesState.fromJson(Map<String, dynamic> j) => ProfilesState(
    profiles: [
      for (final p in (j['profiles'] as List? ?? const []))
        Profile.fromJson(p as Map<String, dynamic>),
    ],
    activeId: j['activeId'] as String?,
  );
}

/// Owns the profile list + active selection, persisting on every change. Ids
/// are supplied by the caller so the controller stays deterministic/testable.
class ProfilesController extends StateNotifier<ProfilesState> {
  final KeyValueStore _store;
  ProfilesController(this._store, ProfilesState initial) : super(initial);

  static const _key = 'profiles';

  static Future<ProfilesState> load(KeyValueStore store) async {
    final raw = await store.get(_key);
    if (raw == null) return const ProfilesState();
    return ProfilesState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  void add(Profile p) {
    final activate = state.profiles.isEmpty; // first profile becomes active
    _set(
      ProfilesState(
        profiles: [...state.profiles, p],
        activeId: activate ? p.id : state.activeId,
      ),
    );
  }

  void update(Profile p) => _set(
    ProfilesState(
      profiles: [for (final e in state.profiles) e.id == p.id ? p : e],
      activeId: state.activeId,
    ),
  );

  void remove(String id) {
    final rest = state.profiles.where((p) => p.id != id).toList();
    _set(
      ProfilesState(
        profiles: rest,
        activeId: state.activeId == id
            ? (rest.isEmpty ? null : rest.first.id)
            : state.activeId,
      ),
    );
  }

  void setActive(String id) =>
      _set(ProfilesState(profiles: state.profiles, activeId: id));

  void _set(ProfilesState next) {
    state = next;
    _store.put(_key, jsonEncode(next.toJson()));
  }
}

/// Overridden in main() with the persisted store + loaded state. The default
/// is an ephemeral in-memory controller so widgets/tests work without setup
/// (an empty profile list simply falls back to the repo's git identity).
final profilesProvider =
    StateNotifierProvider<ProfilesController, ProfilesState>(
      (ref) =>
          ProfilesController(InMemoryKeyValueStore(), const ProfilesState()),
    );
