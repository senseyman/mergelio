import 'package:flutter/material.dart' show ThemeMode;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings.freezed.dart';
part 'settings.g.dart';

/// Persisted app settings. Immutable (freezed), JSON-serialisable for storage.
@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(ThemeMode.dark) ThemeMode themeMode,
    @Default(0xFF6E7BFF) int accentValue,
    @Default(264.0) double leftWidth,
    @Default(360.0) double rightWidth,
    @Default(0.64) double diffHeight,
    @Default(false) bool leftCollapsed,
    // Per-section collapse state in the left panel, keyed by section id.
    @Default({}) Map<String, bool> collapsedSections,
    // Graph meta columns; a column absent from the map is shown.
    @Default({}) Map<String, bool> graphCols,
    @Default(false) bool graphCompact,
    // Graph column widths (px). Branch gutter is a hard width; the rail is a
    // hard width too, clipping the graph when set narrower than it needs. 0
    // means auto-size the rail to the graph.
    @Default(116.0) double graphBranchWidth,
    @Default(0.0) double graphRailWidth,
    // Diff sheet: split vs inline view.
    @Default(false) bool diffSplit,
    // General preferences.
    @Default(false) bool autoFetch,
    // Auto-fetch poll interval in seconds (only used while autoFetch is on).
    @Default(5) int autoFetchIntervalSeconds,
    @Default(true) bool confirmDestructive,
    @Default(true) bool restoreTabs,
    // 'merge' | 'rebase' — default strategy for Pull.
    @Default('merge') String pullStrategy,
    // 'medium' (Jul 2, 2026) | 'iso' (2026-07-02) | 'short' (07/02/26).
    @Default('medium') String dateFormat,
    // '24h' (14:33) | '12h' (2:33 PM) — used wherever a clock is shown.
    @Default('24h') String clockFormat,
    // Per-index branch-palette colour overrides (ARGB); missing = default.
    @Default({}) Map<String, int> branchColorOverrides,
    // Saved themes by name → JSON blob.
    @Default({}) Map<String, String> savedThemes,
    // UI language: '' follows the system locale, else 'en' / 'uk'.
    @Default('') String localeCode,
    // Opt-in anonymised telemetry + crash reporting. Off by default.
    @Default(false) bool telemetryEnabled,
    // UI zoom (text/icon scale), 1.0–2.0 per the 100–200% accessibility NFR.
    @Default(1.0) double uiScale,
    // Repo-group switcher style: 'dropdown' | 'pills' | 'rail'.
    @Default('dropdown') String groupStyle,
    // Terminal dock: open state + height, both restored across sessions.
    @Default(false) bool terminalOpen,
    @Default(240.0) double terminalHeight,
    // Window size, restored on launch.
    @Default(1440.0) double windowWidth,
    @Default(900.0) double windowHeight,
    // Show changed-file lists grouped into a directory tree vs a flat list.
    @Default(true) bool filesAsTree,
    // Files mode: navigator width, and whether gitignored entries are hidden.
    @Default(300.0) double filesNavWidth,
    @Default(false) bool filesHideIgnored,
    @Default(false) bool filesNavCollapsed,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}
