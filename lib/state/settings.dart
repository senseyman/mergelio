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
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}
