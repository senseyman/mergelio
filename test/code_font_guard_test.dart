import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `'monospace'` is a fontconfig alias. It resolves on Linux and Android; on
/// macOS and Windows it matches nothing and text quietly falls back to a
/// proportional face, which shrinks every leading space in code we render.
/// [AppFonts.mns] names a real family and carries a fallback list, so every
/// place that paints code should go through it.
void main() {
  test('no widget asks for the bare "monospace" family', () {
    final offenders = <String>[];
    final pattern = RegExp(r"fontFamily:\s*[^,\n]*'monospace'");

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }

    expect(offenders, isEmpty, reason: 'use AppFonts.mns instead');
  });
}
