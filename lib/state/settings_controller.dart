import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import '../domain/theme_io.dart';
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

  void setAutoFetch(bool v) => _update(state.copyWith(autoFetch: v));

  /// Auto-fetch poll interval, floored at 5s so it cannot hammer the network.
  void setAutoFetchInterval(int seconds) =>
      _update(state.copyWith(autoFetchIntervalSeconds: seconds.clamp(5, 3600)));
  void setConfirmDestructive(bool v) =>
      _update(state.copyWith(confirmDestructive: v));
  void setRestoreTabs(bool v) => _update(state.copyWith(restoreTabs: v));
  void setPullStrategy(String s) => _update(state.copyWith(pullStrategy: s));
  void setDateFormat(String s) => _update(state.copyWith(dateFormat: s));

  /// UI language: '' (system), 'en' or 'uk'.
  void setLocaleCode(String code) => _update(state.copyWith(localeCode: code));

  void setTelemetryEnabled(bool v) =>
      _update(state.copyWith(telemetryEnabled: v));

  /// Group-switcher style: 'dropdown' | 'pills' | 'rail'.
  void setGroupStyle(String s) => _update(state.copyWith(groupStyle: s));

  void toggleFilesAsTree() =>
      _update(state.copyWith(filesAsTree: !state.filesAsTree));

  void toggleTerminal() =>
      _update(state.copyWith(terminalOpen: !state.terminalOpen));
  void setTerminalOpen(bool v) => _update(state.copyWith(terminalOpen: v));
  void setTerminalHeight(double h) =>
      _update(state.copyWith(terminalHeight: h.clamp(140, 520)));

  /// Persists the window size (min-size clamped by the window manager).
  void setWindowSize(double w, double h) =>
      _update(state.copyWith(windowWidth: w, windowHeight: h));

  /// UI zoom, clamped to the 100–200% accessibility range.
  void setUiScale(double v) =>
      _update(state.copyWith(uiScale: v.clamp(1.0, 2.0)));
  void zoomIn() => setUiScale(state.uiScale + 0.1);
  void zoomOut() => setUiScale(state.uiScale - 0.1);
  void zoomReset() => setUiScale(1.0);

  /// Overrides one branch-palette colour (index 0–7).
  void setBranchColor(int index, Color color) {
    final next = Map<String, int>.from(state.branchColorOverrides);
    next['$index'] = color.toARGB32();
    _update(state.copyWith(branchColorOverrides: next));
  }

  void resetBranchColors() =>
      _update(state.copyWith(branchColorOverrides: const {}));

  /// Applies a theme spec: mode, accent and branch colours, all live.
  void applyTheme(ThemeSpec spec) {
    _update(
      state.copyWith(
        themeMode: spec.mode == 'light' ? ThemeMode.light : ThemeMode.dark,
        accentValue: spec.accent,
        branchColorOverrides: {
          for (var i = 0; i < spec.branchColors.length; i++)
            '$i': spec.branchColors[i],
        },
      ),
    );
  }

  /// Current settings as an exportable [ThemeSpec], given the base palette.
  ThemeSpec currentTheme(String name, List<int> basePalette) => ThemeSpec(
    name: name,
    mode: state.themeMode == ThemeMode.light ? 'light' : 'dark',
    accent: state.accentValue,
    branchColors: [
      for (var i = 0; i < basePalette.length; i++)
        state.branchColorOverrides['$i'] ?? basePalette[i],
    ],
  );

  /// Saves the current theme under [name] for later re-apply.
  void saveTheme(String name, List<int> basePalette) {
    final next = Map<String, String>.from(state.savedThemes);
    next[name] = currentTheme(name, basePalette).encode();
    _update(state.copyWith(savedThemes: next));
  }

  /// Applies a previously saved theme by [name]; no-op if it is unknown or
  /// its stored blob no longer decodes.
  void applySavedTheme(String name) {
    final blob = state.savedThemes[name];
    if (blob == null) return;
    try {
      applyTheme(ThemeSpec.decode(blob));
    } on Object {
      // Corrupt blob — bad JSON, wrong value types, unparseable colours —
      // leaves the current theme untouched.
    }
  }

  /// Forgets a saved theme.
  void deleteSavedTheme(String name) {
    if (!state.savedThemes.containsKey(name)) return;
    final next = Map<String, String>.from(state.savedThemes)..remove(name);
    _update(state.copyWith(savedThemes: next));
  }

  void setLeftWidth(double w) =>
      _update(state.copyWith(leftWidth: w.clamp(200, 460)));

  void setRightWidth(double w) =>
      _update(state.copyWith(rightWidth: w.clamp(300, 560)));

  void setFilesNavWidth(double w) =>
      _update(state.copyWith(filesNavWidth: w.clamp(200, 560)));

  void toggleFilesHideIgnored() =>
      _update(state.copyWith(filesHideIgnored: !state.filesHideIgnored));

  void toggleFilesNavCollapsed() =>
      _update(state.copyWith(filesNavCollapsed: !state.filesNavCollapsed));

  void setGraphBranchWidth(double w) =>
      _update(state.copyWith(graphBranchWidth: w.clamp(40, 400)));

  /// Sets the rail's fixed width. Non-positive means auto-size; a dragged value
  /// is floored at 24px so the rail can shrink (clipping the graph) but never
  /// vanish.
  void setGraphRailWidth(double w) =>
      _update(state.copyWith(graphRailWidth: w <= 0 ? 0 : w.clamp(24, 1200)));

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
