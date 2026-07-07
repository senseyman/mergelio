import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';

DiffLine _l(DiffLineType t, String text) => DiffLine(type: t, text: text);

String _changed(List<DiffSeg> segs) =>
    segs.where((s) => s.changed).map((s) => s.text).join('|');

String _all(List<DiffSeg> segs) => segs.map((s) => s.text).join();

void main() {
  group('diffWords', () {
    test('marks only the changed token, keeping shared text intact', () {
      final (del, add) = diffWords('the quick brown fox', 'the slow brown fox');
      expect(_all(del), 'the quick brown fox');
      expect(_all(add), 'the slow brown fox');
      expect(_changed(del), 'quick');
      expect(_changed(add), 'slow');
    });

    test('a pure insertion changes nothing on the deleted side', () {
      final (del, add) = diffWords('a c', 'a b c');
      expect(_changed(del), '');
      expect(_changed(add), 'b');
    });

    test('identical lines have no changed segments', () {
      final (del, add) = diffWords('same text', 'same text');
      expect(_changed(del), '');
      expect(_changed(add), '');
    });

    test('reassembles the exact original text', () {
      final (del, add) = diffWords(
        'int x = compute(a, b);',
        'int y = compute(a, c);',
      );
      expect(_all(del), 'int x = compute(a, b);');
      expect(_all(add), 'int y = compute(a, c);');
    });
  });

  group('annotateWords', () {
    test('pairs each deleted line with the matching added line', () {
      final lines = annotateWords([
        _l(DiffLineType.context, 'unchanged'),
        _l(DiffLineType.del, 'foo old'),
        _l(DiffLineType.add, 'foo new'),
        _l(DiffLineType.context, 'tail'),
      ]);
      expect(lines[0].words, isNull); // context untouched
      expect(_changed(lines[1].words!), 'old');
      expect(_changed(lines[2].words!), 'new');
      expect(lines[3].words, isNull);
    });

    test('leaves a pure addition or deletion without word segments', () {
      final lines = annotateWords([
        _l(DiffLineType.add, 'brand new line'),
        _l(DiffLineType.del, 'removed line'),
      ]);
      expect(lines.every((l) => l.words == null), isTrue);
    });

    test('skips word diff for very long lines to stay cheap', () {
      final long = 'x' * 20000;
      final lines = annotateWords([
        _l(DiffLineType.del, '${long}a'),
        _l(DiffLineType.add, '${long}b'),
      ]);
      // No quadratic LCS over 20k tokens: the pair is left unannotated.
      expect(lines.every((l) => l.words == null), isTrue);
    });

    test('pairs run-for-run when counts match', () {
      final lines = annotateWords([
        _l(DiffLineType.del, 'a1'),
        _l(DiffLineType.del, 'b1'),
        _l(DiffLineType.add, 'a2'),
        _l(DiffLineType.add, 'b2'),
      ]);
      expect(lines.every((l) => l.words != null), isTrue);
    });
  });
}
