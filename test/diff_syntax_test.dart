import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';

SyntaxKind _kindOf(List<SyntaxToken> toks, String text) =>
    toks.firstWhere((t) => t.text == text).kind;

void main() {
  group('highlightLine', () {
    test('reassembles the exact source text', () {
      const src = '  final x = foo(42); // note';
      expect(highlightLine(src).map((t) => t.text).join(), src);
    });

    test('classifies keywords, numbers, strings and comments', () {
      final toks = highlightLine('final n = 42;');
      expect(_kindOf(toks, 'final'), SyntaxKind.keyword);
      expect(_kindOf(toks, '42'), SyntaxKind.number);

      final s = highlightLine('var s = "hi";');
      expect(_kindOf(s, '"hi"'), SyntaxKind.string);

      final c = highlightLine('x // trailing');
      expect(c.last.kind, SyntaxKind.comment);
      expect(c.last.text, '// trailing');
    });

    test('a full-line comment is one comment token', () {
      final toks = highlightLine('# a python comment');
      expect(toks, hasLength(1));
      expect(toks.single.kind, SyntaxKind.comment);
    });

    test('plain identifiers are not keywords', () {
      final toks = highlightLine('foobar baz');
      expect(toks.every((t) => t.kind != SyntaxKind.keyword), isTrue);
    });

    test('the decrement operator is not a comment', () {
      final toks = highlightLine('count--;');
      expect(toks.any((t) => t.kind == SyntaxKind.comment), isFalse);
    });

    test('a number is not glued to a following .method call', () {
      final toks = highlightLine('2.toString()');
      final num = toks.firstWhere((t) => t.kind == SyntaxKind.number);
      expect(num.text, '2');
    });
  });
}
