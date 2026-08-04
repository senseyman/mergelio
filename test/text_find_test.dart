// Finding and replacing inside an open file. The matching is pure, so the
// find bar only has to render what these functions report.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/text_find.dart';

void main() {
  group('matches', () {
    test('every occurrence is reported with its span', () {
      final m = findMatches('one two one', 'one');

      expect(m.map((r) => (r.start, r.end)), [(0, 3), (8, 11)]);
    });

    test('an empty query matches nothing', () {
      expect(findMatches('anything', ''), isEmpty);
    });

    test('an empty text matches nothing', () {
      expect(findMatches('', 'a'), isEmpty);
    });

    test('matching ignores case unless asked not to', () {
      expect(findMatches('Apple apple', 'apple'), hasLength(2));
      expect(
        findMatches('Apple apple', 'apple', caseSensitive: true),
        hasLength(1),
      );
    });

    test('overlapping runs are counted once each, left to right', () {
      // 'aaaa' holds two non-overlapping 'aa', not three overlapping ones.
      final m = findMatches('aaaa', 'aa');

      expect(m.map((r) => r.start), [0, 2]);
    });

    test('a query that is not there reports nothing', () {
      expect(findMatches('one two', 'three'), isEmpty);
    });

    test('regex metacharacters are matched literally', () {
      expect(findMatches('a.b axb', '.'), hasLength(1));
      expect(findMatches(r'cost is $5', r'$5'), hasLength(1));
    });
  });

  group('walking the matches', () {
    final matches = findMatches('one two one two one', 'one');

    test('forward lands on the first match at or after the cursor', () {
      expect(nextMatch(matches, 5), 1);
      expect(nextMatch(matches, 0), 0);
    });

    test('forward wraps around the end', () {
      expect(nextMatch(matches, 100), 0);
    });

    test('backward lands on the last match before the cursor', () {
      // Matches start at 0, 8 and 16; from 10 the one behind is the second.
      expect(nextMatch(matches, 10, forward: false), 1);
    });

    test('backward wraps around the start', () {
      expect(nextMatch(matches, 0, forward: false), matches.length - 1);
    });

    test('with nothing found there is nowhere to go', () {
      expect(nextMatch(const [], 0), isNull);
    });
  });

  group('replacing', () {
    test('every match is replaced', () {
      expect(replaceAllMatches('one two one', 'one', 'ONE'), 'ONE two ONE');
    });

    test('replacing respects the case-sensitivity choice', () {
      expect(replaceAllMatches('Apple apple', 'apple', 'pear'), 'pear pear');
      expect(
        replaceAllMatches('Apple apple', 'apple', 'pear', caseSensitive: true),
        'Apple pear',
      );
    });

    test('the replacement is inserted literally, never re-scanned', () {
      // Replacing 'a' with 'aa' must not run away on its own output.
      expect(replaceAllMatches('aaa', 'a', 'aa'), 'aaaaaa');
    });

    test('a replacement containing a group reference stays literal', () {
      expect(replaceAllMatches(r'x', 'x', r'$1'), r'$1');
    });

    test('an empty query leaves the text alone', () {
      expect(replaceAllMatches('text', '', 'x'), 'text');
    });

    test('replacing one match leaves the rest alone', () {
      final m = findMatches('one two one', 'one');

      expect(replaceMatch('one two one', m[1], 'ONE'), 'one two ONE');
    });
  });
}
