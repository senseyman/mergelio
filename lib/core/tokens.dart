import 'package:flutter/material.dart';

/// Mergelio design tokens. Exposed via [ThemeExtension] so widgets read them
/// with `Theme.of(context).extension<AppTokens>()!`.
///
/// `accent` is overridable at runtime (theme editor); everything else is
/// fixed per theme.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final Color bgApp;
  final Color bgPanel;
  final Color bgElevated;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textMuted;
  final Color textFaint;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color hover;
  final Color active;
  final Color addBg;
  final Color delBg;
  final Color addWord;
  final Color delWord;
  final Color shadow;

  /// Cyclic commit-graph branch palette, customisable.
  final List<Color> branchPalette;

  // Radii
  final double rButton;
  final double rCard;
  final double rPill;

  const AppTokens({
    required this.bgApp,
    required this.bgPanel,
    required this.bgElevated,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.hover,
    required this.active,
    required this.addBg,
    required this.delBg,
    required this.addWord,
    required this.delWord,
    required this.shadow,
    required this.branchPalette,
    this.rButton = 7,
    this.rCard = 10,
    this.rPill = 5,
  });

  /// Node gradient for the brand mark — constant across themes.
  static const Color nodeGradientA = Color(0xFF57A8FF);
  static const Color nodeGradientB = Color(0xFF1E6BF0);

  static const List<Color> defaultBranchPalette = [
    Color(0xFF4C5BF5),
    Color(0xFF0E9F6E),
    Color(0xFFB54708),
    Color(0xFFD92D20),
    Color(0xFF7A5AF8),
    Color(0xFF0BA5EC),
    Color(0xFFDD2590),
    Color(0xFF3E4784),
  ];

  factory AppTokens.light({Color? accent}) => AppTokens(
    bgApp: const Color(0xFFFFFFFF),
    bgPanel: const Color(0xFFFAFBFD),
    bgElevated: const Color(0xFFFFFFFF),
    border: const Color(0xFFE5E8EF),
    borderStrong: const Color(0xFFD3D8E2),
    textPrimary: const Color(0xFF0B0D14),
    textMuted: const Color(0xFF586173),
    // Darkened from #98A1B3 to clear WCAG AA 3:1 on light backgrounds.
    textFaint: const Color(0xFF798295),
    accent: accent ?? const Color(0xFF4C5BF5),
    success: const Color(0xFF0E9F6E),
    warning: const Color(0xFFB54708),
    danger: const Color(0xFFD92D20),
    hover: const Color(0x0B0B0D14),
    active: const Color(0x1A4C5BF5),
    addBg: const Color(0x1A0E9F6E),
    delBg: const Color(0x16D92D20),
    addWord: const Color(0x3D0E9F6E),
    delWord: const Color(0x38D92D20),
    shadow: const Color(0x24101828),
    branchPalette: defaultBranchPalette,
  );

  factory AppTokens.dark({Color? accent}) => AppTokens(
    bgApp: const Color(0xFF0B0D12),
    bgPanel: const Color(0xFF101319),
    bgElevated: const Color(0xFF161A23),
    border: const Color(0xFF242A38),
    borderStrong: const Color(0xFF313A4C),
    textPrimary: const Color(0xFFEAECF3),
    textMuted: const Color(0xFF98A2B6),
    textFaint: const Color(0xFF5E677D),
    accent: accent ?? const Color(0xFF7C8CFF),
    success: const Color(0xFF34D399),
    warning: const Color(0xFFFBBF4B),
    danger: const Color(0xFFF87171),
    hover: const Color(0x0DFFFFFF),
    active: const Color(0x267C8CFF),
    addBg: const Color(0x2134D399),
    delBg: const Color(0x1FF87171),
    addWord: const Color(0x4D34D399),
    delWord: const Color(0x47F87171),
    shadow: const Color(0x80000000),
    branchPalette: defaultBranchPalette,
  );

  Color branchColor(int i) => branchPalette[i % branchPalette.length];

  @override
  AppTokens copyWith({Color? accent, List<Color>? branchPalette}) => AppTokens(
    bgApp: bgApp,
    bgPanel: bgPanel,
    bgElevated: bgElevated,
    border: border,
    borderStrong: borderStrong,
    textPrimary: textPrimary,
    textMuted: textMuted,
    textFaint: textFaint,
    accent: accent ?? this.accent,
    success: success,
    warning: warning,
    danger: danger,
    hover: hover,
    active: active,
    addBg: addBg,
    delBg: delBg,
    addWord: addWord,
    delWord: delWord,
    shadow: shadow,
    branchPalette: branchPalette ?? this.branchPalette,
    rButton: rButton,
    rCard: rCard,
    rPill: rPill,
  );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => a + (b - a) * t;
    return AppTokens(
      bgApp: c(bgApp, other.bgApp),
      bgPanel: c(bgPanel, other.bgPanel),
      bgElevated: c(bgElevated, other.bgElevated),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textMuted: c(textMuted, other.textMuted),
      textFaint: c(textFaint, other.textFaint),
      accent: c(accent, other.accent),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      hover: c(hover, other.hover),
      active: c(active, other.active),
      addBg: c(addBg, other.addBg),
      delBg: c(delBg, other.delBg),
      addWord: c(addWord, other.addWord),
      delWord: c(delWord, other.delWord),
      shadow: c(shadow, other.shadow),
      branchPalette: t < 0.5 ? branchPalette : other.branchPalette,
      rButton: d(rButton, other.rButton),
      rCard: d(rCard, other.rCard),
      rPill: d(rPill, other.rPill),
    );
  }
}

/// Convenience accessor.
extension AppTokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}
