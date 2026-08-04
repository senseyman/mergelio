import 'dart:convert';

/// Undoes the C-style quoting git applies to a path it prints on its own line.
/// Only names holding a quote, a backslash or a control character come back
/// quoted, so an ordinary path passes straight through.
String unquoteGitPath(String value) {
  if (value.length < 2 || !value.startsWith('"') || !value.endsWith('"')) {
    return value;
  }
  final body = value.substring(1, value.length - 1);
  // Escapes are byte-oriented (`\303\274` is one UTF-8 character), so the
  // bytes are collected first and decoded once at the end.
  final bytes = <int>[];
  for (var i = 0; i < body.length; i++) {
    if (body[i] != r'\' || i + 1 == body.length) {
      bytes.addAll(utf8.encode(body[i]));
      continue;
    }
    final escape = body[++i];
    final control = switch (escape) {
      'a' => 7,
      'b' => 8,
      't' => 9,
      'n' => 10,
      'v' => 11,
      'f' => 12,
      'r' => 13,
      '"' => 34,
      r'\' => 92,
      _ => null,
    };
    if (control != null) {
      bytes.add(control);
      continue;
    }
    final octal = _octalAt(body, i);
    if (octal == null) {
      bytes.addAll(utf8.encode(escape));
      continue;
    }
    bytes.add(octal);
    i += 2;
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// The byte written as three octal digits starting at [at], or null when what
/// follows the backslash is not one.
int? _octalAt(String body, int at) {
  if (at + 2 >= body.length) return null;
  var value = 0;
  for (var i = at; i < at + 3; i++) {
    final digit = body.codeUnitAt(i) - 0x30;
    if (digit < 0 || digit > 7) return null;
    value = value * 8 + digit;
  }
  return value;
}
