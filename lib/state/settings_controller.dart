import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import 'settings.dart';

/// Owns [AppSettings], applies mutations, and persists on every change.
class SettingsController extends StateNotifier<AppSettings> {
  final SettingsRepository repo;
  SettingsController(this.repo, AppSettings initial) : super(initial);

  void setThemeMode(ThemeMode mode) => _update(state.copyWith(themeMode: mode));

  void toggleTheme() => setThemeMode(
    state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
  );

  void setAccent(Color color) =>
      _update(state.copyWith(accentValue: color.toARGB32()));

  void setLeftWidth(double w) =>
      _update(state.copyWith(leftWidth: w.clamp(200, 460)));

  void setRightWidth(double w) =>
      _update(state.copyWith(rightWidth: w.clamp(300, 560)));

  void toggleLeftCollapsed() =>
      _update(state.copyWith(leftCollapsed: !state.leftCollapsed));

  /// Flips the collapse state of a left-panel section (default expanded).
  void toggleSection(String id) {
    final next = Map<String, bool>.from(state.collapsedSections);
    next[id] = !(next[id] ?? false);
    _update(state.copyWith(collapsedSections: next));
  }

  /// Flips a graph meta column (default shown).
  void toggleGraphCol(String id) {
    final next = Map<String, bool>.from(state.graphCols);
    next[id] = !(next[id] ?? true);
    _update(state.copyWith(graphCols: next));
  }

  void toggleGraphCompact() =>
      _update(state.copyWith(graphCompact: !state.graphCompact));

  void setDiffSplit(bool split) => _update(state.copyWith(diffSplit: split));

  void setDiffHeight(double h) =>
      _update(state.copyWith(diffHeight: h.clamp(0.28, 0.86)));

  void _update(AppSettings next) {
    state = next;
    // Persistence is best-effort per change; a failed write must not crash
    // the UI, but is never an unhandled async error either.
    repo.save(next).catchError((Object e) {
      debugPrint('settings: save failed: $e');
    });
  }
}

/// Overridden in `main()` with the loaded initial state + repository.
final settingsProvider = StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => throw UnimplementedError('settingsProvider must be overridden'),
);
