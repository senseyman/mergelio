import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/ui/preferences/preferences_dialog.dart';

void main() {
  test('parses #RRGGBB to opaque ARGB', () {
    expect(parseHexColor('#6E7BFF'), 0xFF6E7BFF);
    expect(parseHexColor('6e7bff'), 0xFF6E7BFF);
  });

  test('parses 8-digit #AARRGGBB by dropping the alpha byte', () {
    expect(parseHexColor('#8012ABCD'), 0xFF12ABCD);
  });

  test('rejects malformed input', () {
    expect(parseHexColor('#12'), isNull);
    expect(parseHexColor('nothex!'), isNull);
    expect(parseHexColor(''), isNull);
  });
}
