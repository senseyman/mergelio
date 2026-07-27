import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/ui/diff/syntax_style.dart';

void main() {
  final t = AppTokens.dark();
  const base = TextStyle(fontSize: 12);

  String flatten(TextSpan span) {
    final buf = StringBuffer();
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null) buf.write(s.text);
      return true;
    });
    return buf.toString();
  }

  /// The editor maps caret offsets through these spans, so every character of
  /// the source has to survive tokenising in its original order.
  group('spans reproduce the text exactly', () {
    for (final sample in <String>[
      'final x = 1;',
      '  indented("with args");\n\ttab indented\n',
      'line one\nline two\nline three',
      'trailing newline\n',
      '\n\n\n',
      '',
      'const s = "a string with  double  spaces";',
      '// a comment\nint n = 42; // trailing comment',
      "unicode ‚Äî em dash and √©accent",
    ]) {
      test(jsonish(sample), () {
        expect(flatten(syntaxSpans(sample, base, t)), sample);
      });
    }
  });

  test('keywords, strings, numbers and comments each get their colour', () {
    final span = syntaxSpans('const s = "x"; // note 7', base, t);
    final colours = <String, Color?>{};
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null && s.text!.trim().isNotEmpty) {
        colours[s.text!] = s.style?.color;
      }
      return true;
    });

    expect(colours['const'], syntaxColor(t, SyntaxKind.keyword));
    expect(colours['"x"'], syntaxColor(t, SyntaxKind.string));
    expect(colours['// note 7'], syntaxColor(t, SyntaxKind.comment));
  });

  test('a file past the highlight cap is left unstyled but intact', () {
    final big = 'const x = 1;\n' * ((maxHighlightChars ~/ 13) + 2);
    expect(big.length, greaterThan(maxHighlightChars));

    final span = syntaxSpans(big, base, t);
    expect(span.children, isNull);
    expect(span.text, big);
  });
}

/// Readable test names for samples containing newlines and tabs.
String jsonish(String s) =>
    s.isEmpty ? '(empty)' : s.replaceAll('\n', r'\n').replaceAll('\t', r'\t');
