import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/theme_io.dart';

void main() {
  group('ThemeSpec', () {
    const spec = ThemeSpec(
      name: 'mergelio-custom',
      mode: 'dark',
      accent: 0xFF7C8CFF,
      branchColors: [
        0xFF4C5BF5,
        0xFF0E9F6E,
        0xFFB54708,
        0xFFD92D20,
        0xFF7A5AF8,
        0xFF0BA5EC,
        0xFFDD2590,
        0xFF3E4784,
      ],
    );

    test('encodes accent and branch colours as #RRGGBB', () {
      final json = spec.toJson();
      expect(json['accent'], '#7C8CFF');
      expect(json['theme'], 'dark');
      expect((json['branchColors'] as List).first, '#4C5BF5');
    });

    test('export → import round-trips', () {
      final back = ThemeSpec.decode(spec.encode());
      expect(back.name, spec.name);
      expect(back.mode, spec.mode);
      expect(back.accent, spec.accent);
      expect(back.branchColors, spec.branchColors);
    });

    test(
      'parses a hand-written export with lowercase hex + alpha stripped',
      () {
        final s = ThemeSpec.decode(
          '{"name":"x","theme":"light","accent":"#abcdef",'
          '"branchColors":["#111111","#222222"]}',
        );
        expect(s.mode, 'light');
        expect(s.accent, 0xFFABCDEF);
        expect(s.branchColors, [0xFF111111, 0xFF222222]);
      },
    );

    test('parses 8-digit #AARRGGBB by taking the RGB bytes', () {
      final s = ThemeSpec.decode(
        '{"name":"x","theme":"dark","accent":"#FF6E7BFF",'
        '"branchColors":["#8012ABCD"]}',
      );
      // Alpha byte (FF / 80) dropped; RGB preserved, opaque.
      expect(s.accent, 0xFF6E7BFF);
      expect(s.branchColors, [0xFF12ABCD]);
    });
  });
}
