import 'dart:convert';

/// A saveable/exportable theme: mode, accent and the 8 branch colours. Colours
/// are hex strings (#RRGGBB) in the JSON to match the spec's export format.
class ThemeSpec {
  final String name;
  final String mode; // 'dark' | 'light'
  final int accent; // ARGB
  final List<int> branchColors; // ARGB, length 8
  const ThemeSpec({
    required this.name,
    required this.mode,
    required this.accent,
    required this.branchColors,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'theme': mode,
    'accent': _hex(accent),
    'branchColors': [for (final c in branchColors) _hex(c)],
  };

  factory ThemeSpec.fromJson(Map<String, dynamic> j) => ThemeSpec(
    name: (j['name'] as String?) ?? 'imported',
    mode: (j['theme'] as String?) == 'light' ? 'light' : 'dark',
    accent: _parseHex(j['accent'] as String? ?? '#6E7BFF'),
    branchColors: [
      for (final c in (j['branchColors'] as List? ?? const []))
        _parseHex(c as String),
    ],
  );

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
  static ThemeSpec decode(String raw) =>
      ThemeSpec.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// #RRGGBB from an ARGB int (alpha forced opaque on the way back in).
String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

int _parseHex(String s) {
  final clean = s.replaceAll('#', '').trim();
  // 8-digit is #AARRGGBB (matches our alpha-first ARGB ints) — the RGB is the
  // last six chars; 6-digit is plain #RRGGBB.
  final hex = clean.length == 8
      ? clean.substring(2)
      : (clean.length >= 6 ? clean.substring(0, 6) : clean);
  return 0xFF000000 | int.parse(hex, radix: 16);
}
