import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/contrast.dart';
import 'package:mergelio/core/tokens.dart';

/// Enforces WCAG 2.1 contrast across both themes so a token tweak can never
/// silently regress readability. Content text (primary/muted) must meet AA for
/// normal text (4.5:1); the deliberately-subdued "faint" token, used only for
/// small secondary labels and separators, must meet the 3:1 large-text/UI floor.
void main() {
  final themes = {'light': AppTokens.light(), 'dark': AppTokens.dark()};

  for (final entry in themes.entries) {
    final name = entry.key;
    final t = entry.value;
    final backgrounds = {
      'bgApp': t.bgApp,
      'bgPanel': t.bgPanel,
      'bgElevated': t.bgElevated,
    };

    group('$name theme', () {
      for (final bg in backgrounds.entries) {
        test('textPrimary on ${bg.key} ≥ 4.5:1', () {
          expect(
            contrastRatio(t.textPrimary, bg.value),
            greaterThanOrEqualTo(4.5),
          );
        });
        test('textMuted on ${bg.key} ≥ 4.5:1', () {
          expect(
            contrastRatio(t.textMuted, bg.value),
            greaterThanOrEqualTo(4.5),
          );
        });
        test('textFaint on ${bg.key} ≥ 3:1', () {
          expect(
            contrastRatio(t.textFaint, bg.value),
            greaterThanOrEqualTo(3.0),
          );
        });
      }

      // Non-text UI colours (accent + status) must meet the 3:1 graphical-
      // object / large-text minimum on every surface they can appear on.
      final uiColors = {
        'accent': t.accent,
        'success': t.success,
        'warning': t.warning,
        'danger': t.danger,
      };
      for (final bg in backgrounds.entries) {
        for (final ui in uiColors.entries) {
          test('${ui.key} on ${bg.key} ≥ 3:1', () {
            expect(
              contrastRatio(ui.value, bg.value),
              greaterThanOrEqualTo(3.0),
            );
          });
        }
      }
    });
  }

  test('sanity: black on white is ~21:1, identical colours are 1:1', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.5),
    );
    expect(
      contrastRatio(const Color(0xFF123456), const Color(0xFF123456)),
      1.0,
    );
  });
}
