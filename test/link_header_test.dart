import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/link_header.dart';

/// The request whose response carried the headers below. Every usable
/// next page has to sit on this same host.
final _from = Uri.parse('https://api.github.com/repos/o/r/pulls');

void main() {
  group('nextPageUrl', () {
    test('finds the next link among several', () {
      const header =
          '<https://api.github.com/repos/o/r/pulls?page=2>; rel="next", '
          '<https://api.github.com/repos/o/r/pulls?page=9>; rel="last"';
      expect(
        nextPageUrl(header, requestedFrom: _from),
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
        nextPageUrl(header, requestedFrom: _from),
        Uri.parse('https://api.github.com/repos/o/r/pulls?page=3'),
      );
    });

    test('returns null on the last page, where only prev and first exist', () {
      const header =
          '<https://api.github.com/repos/o/r/pulls?page=8>; rel="prev", '
          '<https://api.github.com/repos/o/r/pulls?page=1>; rel="first"';
      expect(nextPageUrl(header, requestedFrom: _from), isNull);
    });

    test('returns null for an absent or empty header', () {
      expect(nextPageUrl(null, requestedFrom: _from), isNull);
      expect(nextPageUrl('', requestedFrom: _from), isNull);
      expect(nextPageUrl('   ', requestedFrom: _from), isNull);
    });

    test('tolerates unusual spacing and single quotes around rel', () {
      const header = "<https://api.github.com/x?page=2>;rel='next'";
      expect(
        nextPageUrl(header, requestedFrom: _from),
        Uri.parse('https://api.github.com/x?page=2'),
      );
    });

    test('ignores a malformed section instead of throwing', () {
      const header = 'garbage, <https://api.github.com/x?page=2>; rel="next"';
      expect(
        nextPageUrl(header, requestedFrom: _from),
        Uri.parse('https://api.github.com/x?page=2'),
      );
    });

    test('returns null when nothing parses', () {
      expect(nextPageUrl('garbage; rel="next"', requestedFrom: _from), isNull);
      expect(
        nextPageUrl('<not a url>; rel="next"', requestedFrom: _from),
        isNull,
      );
    });

    test('ignores a next link that is not https', () {
      // A paging URL comes from the server; it must not downgrade transport.
      expect(
        nextPageUrl(
          '<http://api.github.com/x>; rel="next"',
          requestedFrom: _from,
        ),
        isNull,
      );
    });

    test('does not match a rel that merely starts with next', () {
      expect(
        nextPageUrl(
          '<https://api.github.com/x>; rel="nextish"',
          requestedFrom: _from,
        ),
        isNull,
      );
    });

    test('matches rel regardless of case', () {
      const header = '<https://api.github.com/x?page=2>; REL="NEXT"';
      expect(
        nextPageUrl(header, requestedFrom: _from),
        Uri.parse('https://api.github.com/x?page=2'),
      );
    });

    test('a stray angle bracket does not glue the sections together', () {
      // The scanner only counts '>' while it is inside a section. If it
      // counted one at depth zero the depth would go negative, no later
      // comma would split anything, and the whole header would collapse
      // into a single section whose first URL wins — here the prev link.
      const header =
          '> stray, '
          '<https://api.github.com/x?page=1>; rel="prev", '
          '<https://api.github.com/x?page=2>; rel="next"';
      expect(
        nextPageUrl(header, requestedFrom: _from),
        Uri.parse('https://api.github.com/x?page=2'),
      );
    });

    test('a url containing a comma does not truncate its section', () {
      // Splitting the whole header on ',' before looking for '<...>'
      // sections cuts a URL like this one in half, at the comma inside its
      // own query string, before the URL is ever parsed.
      const header =
          '<https://api.github.com/repos/o/r/issues?cursor=a,b>; rel="next", '
          '<https://api.github.com/repos/o/r/issues?page=1>; rel="prev"';
      expect(
        nextPageUrl(header, requestedFrom: _from),
        Uri.parse('https://api.github.com/repos/o/r/issues?cursor=a,b'),
      );
    });

    test(
      'a comma inside one url does not stop the next section being found',
      () {
        const header =
            '<https://api.github.com/x?a=1,2>; rel="prev", '
            '<https://api.github.com/x?page=3>; rel="next"';
        expect(
          nextPageUrl(header, requestedFrom: _from),
          Uri.parse('https://api.github.com/x?page=3'),
        );
      },
    );

    test('refuses a next link that names another host', () {
      // Whoever answers a request also writes this header, so an unchecked
      // next link points the caller's token at any host it likes.
      const header = '<https://evil.example.com/pulls?page=2>; rel="next"';
      expect(nextPageUrl(header, requestedFrom: _from), isNull);
    });

    test('refuses a next link that crosses between the two forges', () {
      const header = '<https://gitlab.com/api/v4/projects/1/x>; rel="next"';
      expect(nextPageUrl(header, requestedFrom: _from), isNull);
      expect(
        nextPageUrl(
          '<https://api.github.com/repos/o/r/pulls?page=2>; rel="next"',
          requestedFrom: Uri.parse('https://gitlab.com/api/v4/projects/1/x'),
        ),
        isNull,
      );
    });

    test('refuses a next link on another port of the same host', () {
      // A different port is a different service, even on the same machine.
      const header = '<https://api.github.com:8443/x?page=2>; rel="next"';
      expect(nextPageUrl(header, requestedFrom: _from), isNull);
    });

    test('refuses a host that merely ends with the expected one', () {
      const header = '<https://notapi.github.com/x?page=2>; rel="next"';
      expect(nextPageUrl(header, requestedFrom: _from), isNull);
      expect(
        nextPageUrl(
          '<https://api.github.com.evil.example/x>; rel="next"',
          requestedFrom: _from,
        ),
        isNull,
      );
    });

    test('accepts a host spelled in a different case', () {
      // Host names are case-insensitive, so this is the same host and
      // refusing it would break paging for no gain.
      const header =
          '<https://API.GitHub.com/repos/o/r/pulls?page=2>; '
          'rel="next"';
      expect(
        nextPageUrl(header, requestedFrom: _from),
        Uri.parse('https://API.GitHub.com/repos/o/r/pulls?page=2'),
      );
    });
  });
}
