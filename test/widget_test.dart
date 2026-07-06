import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';

void main() {
  test('AppTokens expose the exact spec colours', () {
    final lt = AppTokens.light();
    final dt = AppTokens.dark();

    expect(lt.bgApp, const Color(0xFFFFFFFF));
    expect(dt.bgApp, const Color(0xFF0B0D12));
    expect(lt.accent, const Color(0xFF4C5BF5));
    expect(dt.accent, const Color(0xFF7C8CFF));
    expect(lt.success, const Color(0xFF0E9F6E));
    expect(dt.danger, const Color(0xFFF87171));
  });

  test('branch palette is cyclic and 8-wide', () {
    final t = AppTokens.dark();
    expect(t.branchPalette.length, 8);
    expect(t.branchColor(8), t.branchColor(0));
    expect(t.branchColor(9), t.branchColor(1));
  });

  test('custom accent overrides the theme default', () {
    final t = AppTokens.light(accent: const Color(0xFF123456));
    expect(t.accent, const Color(0xFF123456));
  });
}
