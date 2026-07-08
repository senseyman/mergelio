import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Typography families: Space Grotesk (display), Inter (body), JetBrains Mono (code).
class AppFonts {
  static String get display => GoogleFonts.spaceGrotesk().fontFamily!;
  static String get body => GoogleFonts.inter().fontFamily!;
  static String get mono => GoogleFonts.jetBrainsMono().fontFamily!;

  static TextStyle disp({
    double size = 16,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) => GoogleFonts.spaceGrotesk(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: -0.2,
  );

  static TextStyle mns({double size = 12, Color? color}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color);
}

/// Builds a [ThemeData] for the given [brightness] using Mergelio tokens.
/// [accent] overrides the theme's default accent (user-customisable in the theme editor).
ThemeData buildTheme(
  Brightness brightness, {
  Color? accent,
  List<Color>? branchPalette,
}) {
  var tokens = brightness == Brightness.dark
      ? AppTokens.dark(accent: accent)
      : AppTokens.light(accent: accent);
  if (branchPalette != null) {
    tokens = tokens.copyWith(branchPalette: branchPalette);
  }

  final base = ThemeData(brightness: brightness, useMaterial3: true);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: tokens.accent,
        brightness: brightness,
      ).copyWith(
        primary: tokens.accent,
        surface: tokens.bgApp,
        onSurface: tokens.textPrimary,
        outline: tokens.border,
        error: tokens.danger,
      );

  return base.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.bgApp,
    canvasColor: tokens.bgApp,
    dividerColor: tokens.border,
    textTheme: GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: tokens.textPrimary, displayColor: tokens.textPrimary),
    extensions: [tokens],
    splashFactory: NoSplash.splashFactory,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: brightness == Brightness.dark
            ? const Color(0xFF0A0B14)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.rButton),
        ),
      ),
    ),
  );
}
