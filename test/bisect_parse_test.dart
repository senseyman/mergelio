import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/bisect.dart';

void main() {
  group('parseBisectRefs', () {
    test('reads bad, good and skip marks', () {
      final marks = parseBisectRefs(
        'aaa1111 refs/bisect/bad\n'
        'bbb2222 refs/bisect/good-bbb2222\n'
        'ccc3333 refs/bisect/skip-ccc3333\n',
      );
      expect(marks, hasLength(3));
      expect(marks[0].sha, 'aaa1111');
      expect(marks[0].kind, BisectKind.bad);
      expect(marks[1].kind, BisectKind.good);
      expect(marks[2].kind, BisectKind.skip);
    });

    test('takes the sha from the ref target, not the name suffix', () {
      // git writes the same sha in both places, but the target is what the
      // ref actually points at, so that is the one to trust.
      final marks = parseBisectRefs('deadbee refs/bisect/good-ffffffff\n');
      expect(marks.single.sha, 'deadbee');
    });

    test('ignores blank lines and unrecognised refs', () {
      final marks = parseBisectRefs(
        '\n'
        'aaa1111 refs/bisect/bad\n'
        'ddd4444 refs/bisect/something-else\n',
      );
      expect(marks, hasLength(1));
      expect(marks.single.kind, BisectKind.bad);
    });

    test('empty output yields no marks', () {
      expect(parseBisectRefs(''), isEmpty);
    });
  });

  group('parseBisectTerms', () {
    test('reads the bad term from line 1 and the good term from line 2', () {
      final t = parseBisectTerms('broken\nworking\n');
      expect(t.bad, 'broken');
      expect(t.good, 'working');
    });

    test('null contents fall back to good and bad', () {
      final t = parseBisectTerms(null);
      expect(t.bad, 'bad');
      expect(t.good, 'good');
    });

    test('a single-line file falls back rather than guessing', () {
      final t = parseBisectTerms('broken\n');
      expect(t.bad, 'bad');
      expect(t.good, 'good');
    });
  });
}
