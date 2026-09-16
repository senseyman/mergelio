import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/link_header.dart';

void main() {
  group('nextPageUrl', () {
    test('finds the next link among several', () {
      const header =
          '<https://api.github.com/repos/o/r/pulls?page=2>; rel="next", '
          '<https://api.github.com/repos/o/r/pulls?page=9>; rel="last"';
      expect(
        nextPageUrl(header),
        Uri.parse('https://api.github.com/repos/o/r/pulls?page=2'),
      );
    });

    test('keeps scanning past a section whose rel is not next', () {
      // Every page but the first leads with prev. Stopping at the first
      // non-matching section would strand the pager on page two.
      const header =
          '<https://api.github.com/repos/o/r/pulls?page=1>; rel="prev", '
          '<https://api.github.com/repos/o/r/pulls?page=3>; rel="next", '
          '<https://api.github.com/repos/o/r/pulls?page=9>; rel="last"';
      expect(
        nextPageUrl(header),
        Uri.parse('https://api.github.com/repos/o/r/pulls?page=3'),
      );
    });

    test('returns null on the last page, where only prev and first exist', () {
      const header =
          '<https://api.github.com/repos/o/r/pulls?page=8>; rel="prev", '
          '<https://api.github.com/repos/o/r/pulls?page=1>; rel="first"';
      expect(nextPageUrl(header), isNull);
    });

    test('returns null for an absent or empty header', () {
      expect(nextPageUrl(null), isNull);
      expect(nextPageUrl(''), isNull);
      expect(nextPageUrl('   '), isNull);
    });

    test('tolerates unusual spacing and single quotes around rel', () {
      const header = "<https://api.github.com/x?page=2>;rel='next'";
      expect(nextPageUrl(header), Uri.parse('https://api.github.com/x?page=2'));
    });

    test('ignores a malformed section instead of throwing', () {
      const header = 'garbage, <https://api.github.com/x?page=2>; rel="next"';
      expect(nextPageUrl(header), Uri.parse('https://api.github.com/x?page=2'));
    });

    test('returns null when nothing parses', () {
      expect(nextPageUrl('garbage; rel="next"'), isNull);
      expect(nextPageUrl('<not a url>; rel="next"'), isNull);
    });

    test('ignores a next link that is not https', () {
      // A paging URL comes from the server; it must not downgrade transport.
      expect(nextPageUrl('<http://api.github.com/x>; rel="next"'), isNull);
    });

    test('does not match a rel that merely starts with next', () {
      expect(nextPageUrl('<https://api.github.com/x>; rel="nextish"'), isNull);
    });

    test('matches rel regardless of case', () {
      const header = '<https://api.github.com/x?page=2>; REL="NEXT"';
      expect(nextPageUrl(header), Uri.parse('https://api.github.com/x?page=2'));
    });
  });
}
