import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blame.dart';

void main() {
  group('parseBlame', () {
    test('parses sha, author and content per line', () {
      const raw = '''
a1b2c3d4e5f6 1 1 2
author Maria K
author-mail <maria@e.com>
author-time 1700000000
summary first
	line one
a1b2c3d4e5f6 2 2
author Maria K
	line two
9f8e7d6c5b4a 3 3 1
author Ivan P
author-mail <ivan@e.com>
	line three
''';
      final lines = parseBlame(raw);
      expect(lines, hasLength(3));
      expect(lines[0].content, 'line one');
      expect(lines[0].author, 'Maria K');
      expect(lines[0].shortSha, 'a1b2c3d');
      expect(lines[2].author, 'Ivan P');
      expect(lines[2].content, 'line three');
    });

    test('tab-prefixed content that itself looks like a header is kept', () {
      // A source line beginning with a hex-like token must not be read as a
      // blame header (it is tab-prefixed).
      const raw = 'abc1234 1 1 1\nauthor T\n\tabc1234 is a token\n';
      final lines = parseBlame(raw);
      expect(lines.single.content, 'abc1234 is a token');
    });
  });
}
