import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tokens.dart';
import '../domain/theme_io.dart';
import 'operation_journal.dart';
import 'profiles.dart';
import 'settings_controller.dart';

/// Per-profile theming: each profile remembers its own theme (mode, accent,
/// branch colours). Switching the active profile snapshots the outgoing
/// profile's theme and applies the incoming one's, so identities keep their
/// look across switches and restarts.
class ProfileThemeSync {
  final Ref _ref;
  String? _lastId;

  ProfileThemeSync(this._ref) {
    _lastId = _ref.read(profilesProvider).activeId;
    _ref.listen(profilesProvider.select((s) => s.activeId), (prev, next) {
      if (prev == next) return;
      _onSwitch(prev ?? _lastId, next);
      _lastId = next;
    });
  }

  static String _key(String profileId) => 'profileTheme:$profileId';

  Future<void> _onSwitch(String? from, String? to) async {
    final store = _ref.read(kvStoreProvider);
    final settings = _ref.read(settingsProvider.notifier);
    try {
      if (from != null) {
        final spec = settings.currentTheme(from, [
          for (final c in AppTokens.defaultBranchPalette) c.toARGB32(),
        ]);
        await store.put(_key(from), spec.encode());
      }
      if (to != null) {
        final raw = await store.get(_key(to));
        if (raw != null) settings.applyTheme(ThemeSpec.decode(raw));
      }
    } on Object catch (e) {
      // Theme sync is cosmetic; never let it break a profile switch.
      debugPrint('profile theme sync failed: $e');
    }
  }
}

/// Kept alive by the app shell.
final profileThemeSyncProvider = Provider<ProfileThemeSync>(
  ProfileThemeSync.new,
);
