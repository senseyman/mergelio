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
    // Diff sheet: split vs inline view.
    @Default(false) bool diffSplit,
    // General preferences.
    @Default(false) bool autoFetch,
    @Default(true) bool confirmDestructive,
    @Default(true) bool restoreTabs,
    // 'merge' | 'rebase' — default strategy for Pull.
    @Default('merge') String pullStrategy,
    // 'medium' (Jul 2, 2026) | 'iso' (2026-07-02) | 'short' (07/02/26).
    @Default('medium') String dateFormat,
    // Per-index branch-palette colour overrides (ARGB); missing = default.
    @Default({}) Map<String, int> branchColorOverrides,
    // Saved themes by name → JSON blob.
    @Default({}) Map<String, String> savedThemes,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}
