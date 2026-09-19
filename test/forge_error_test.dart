import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge_error.dart';

void main() {
  group('forgeErrorForStatus', () {
    test('401 is an authentication failure', () {
      expect(forgeErrorForStatus(401, const {}), isA<ForgeUnauthenticated>());
    });

    test('403 with an exhausted rate limit reports when it resets', () {
      final e = forgeErrorForStatus(403, const {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '1789000000',
      });
      expect(e, isA<ForgeRateLimited>());
      expect(
        (e as ForgeRateLimited).resetAt,
        DateTime.fromMillisecondsSinceEpoch(1789000000 * 1000, isUtc: true),
      );
    });

    test('429 is a rate limit even without GitHub-style headers', () {
      final e = forgeErrorForStatus(429, const {});
      expect(e, isA<ForgeRateLimited>());
      expect((e as ForgeRateLimited).resetAt, isNull);
    });

    test('reads the GitLab spelling of the reset header', () {
      final e = forgeErrorForStatus(429, const {
        'ratelimit-reset': '1789000000',
      });
      expect((e as ForgeRateLimited).resetAt, isNotNull);
    });

    test('a plain 403 is a visibility failure, not a rate limit', () {
      // An under-scoped token gets 403 from some endpoints; saying "rate
      // limited" there would send the user to wait instead of to their scopes.
      expect(forgeErrorForStatus(403, const {}), isA<ForgeNotVisible>());
    });

    test('a scope-limited 403 is a visibility failure even though GitHub still '
        'sends rate-limit headers on it', () {
      // GitHub attaches x-ratelimit-reset (and remaining) to every REST
      // response, success or not, so their mere presence must not be read
      // as "you are rate limited" — only exhaustion is.
      final e = forgeErrorForStatus(403, const {
        'x-ratelimit-remaining': '4321',
        'x-ratelimit-reset': '1789000000',
      });
      expect(e, isA<ForgeNotVisible>());
    });

    test('404 is a visibility failure', () {
      expect(forgeErrorForStatus(404, const {}), isA<ForgeNotVisible>());
    });

    test('5xx is a server fault carrying its status', () {
      final e = forgeErrorForStatus(502, const {});
      expect(e, isA<ForgeServerFault>());
      expect((e as ForgeServerFault).status, 502);
    });

    test('an unexpected status is still a server fault, never a success', () {
      expect(forgeErrorForStatus(418, const {}), isA<ForgeServerFault>());
    });

    test('ignores an unparseable reset header rather than throwing', () {
      final e = forgeErrorForStatus(429, const {'ratelimit-reset': 'soon'});
      expect((e as ForgeRateLimited).resetAt, isNull);
    });
  });

  group('ForgeError', () {
    test('every variant produces a non-empty description', () {
      final errors = <ForgeError>[
        const ForgeUnauthenticated(),
        const ForgeRateLimited(null),
        const ForgeNotVisible(),
        const ForgeOffline('Connection refused'),
        const ForgeServerFault(500),
        const ForgeMalformed('expected a list'),
      ];
      for (final e in errors) {
        expect(e.toString(), isNotEmpty);
      }
    });

    test('ForgeOffline and ForgeMalformed echo detail verbatim, so a caller '
        'must never put a token into detail', () {
      // detail is interpolated raw into toString(); this documents that
      // hazard rather than pretending it away. Redaction is the caller's
      // responsibility at the point detail is constructed, not here.
      const token = 'ghp_secretvalue';
      expect(const ForgeOffline(token).toString(), contains(token));
      expect(const ForgeMalformed(token).toString(), contains(token));
    });
  });
}
