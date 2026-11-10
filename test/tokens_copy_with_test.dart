import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';

/// `copyWith` is how the user's accent and branch colours reach the theme;
/// everything else must come through untouched.
void main() {
  final base = AppTokens.dark();

  List<Object> fixed(AppTokens t) => [
    t.bgApp,
    t.bgPanel,
    t.bgElevated,
    t.border,
    t.borderStrong,
    t.textPrimary,
    t.textMuted,
    t.textFaint,
    t.success,
    t.warning,
    t.danger,
    t.hover,
    t.active,
    t.addBg,
    t.delBg,
    t.addWord,
    t.delWord,
    t.shadow,
    t.rButton,
    t.rCard,
    t.rPill,
  ];

  test('with no arguments it is an exact copy', () {
    final copy = base.copyWith();
    expect(fixed(copy), fixed(base));
    expect(copy.accent, base.accent);
    expect(copy.branchPalette, base.branchPalette);
  });

  test('replaces only the accent', () {
    const pink = Color(0xFFFF00AA);
    final copy = base.copyWith(accent: pink);
    expect(copy.accent, pink);
    expect(fixed(copy), fixed(base));
    expect(copy.branchPalette, base.branchPalette);
  });

  test('replaces only the branch palette', () {
    const palette = [Color(0xFF000001), Color(0xFF000002)];
    final copy = base.copyWith(branchPalette: palette);
    expect(copy.branchPalette, palette);
    expect(copy.accent, base.accent);
    expect(fixed(copy), fixed(base));
    // The graph cycles through the new palette.
    expect(copy.branchColor(0), palette[0]);
    expect(copy.branchColor(3), palette[1]);
  });

  test('light and dark keep their own surfaces under a shared accent', () {
    const accent = Color(0xFF123456);
    final light = AppTokens.light(accent: accent);
    final dark = AppTokens.dark(accent: accent);
    expect(light.accent, dark.accent);
    expect(light.bgApp, isNot(dark.bgApp));
  });
}
