import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';

final _url = Uri.parse('https://api.github.com/repos/o/r/pulls');

/// Builds a response the way MockClient expects one.
http.Response _response(
  String body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.Response(body, status, headers: headers);

void main() {
  group('ForgeHttp.get', () {
    test('sends API headers and bearer token', () async {
      late http.Request seen;
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((req) async {
          seen = req;
          return _response('[]');
        }),
        token: const ForgeToken('ghp_x'),
      );

      await forge.get(_url);

      expect(seen.headers['authorization'], 'Bearer ghp_x');
      expect(seen.headers['accept'], 'application/vnd.github+json');
      expect(seen.headers['x-github-api-version'], '2022-11-28');
    });

    test('omits authorization header when there is no token', () async {
      late http.Request seen;
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((req) async {
          seen = req;
          return _response('[]');
        }),
      );

      await forge.get(_url);

      expect(seen.headers.containsKey('authorization'), isFalse);
    });

    test('sends if-none-match when a caller passes one', () async {
      late http.Request seen;
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((req) async {
          seen = req;
          return _response('[]');
        }),
      );

      await forge.get(_url, ifNoneMatch: 'W/"abc"');

      expect(seen.headers['if-none-match'], 'W/"abc"');
    });

    test('surfaces the response etag', () async {
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient(
          (_) async => _response('[1]', headers: {'etag': 'W/"abc"'}),
        ),
      );

      final res = await forge.get(_url);

      expect(res.status, 200);
      expect(res.body, '[1]');
      expect(res.etag, 'W/"abc"');
    });

    test('returns a 304 response rather than an error', () async {
      // A conditional hit is success: the caller serves it from cache.
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((_) async => _response('', status: 304)),
      );

      final res = await forge.get(_url);

      expect(res.status, 304);
    });

    test('maps a failing status through forgeErrorForStatus', () async {
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((_) async => _response('', status: 401)),
      );

      await expectLater(forge.get(_url), throwsA(isA<ForgeUnauthenticated>()));
    });

    test('maps a rate-limited 403 using its headers', () async {
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient(
          (_) async => _response(
            '',
            status: 403,
            headers: {
              'x-ratelimit-remaining': '0',
              'x-ratelimit-reset': '1789000000',
            },
          ),
        ),
      );

      await expectLater(forge.get(_url), throwsA(isA<ForgeRateLimited>()));
    });

    test('turns a socket failure into ForgeOffline', () async {
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((_) async => throw const SocketException('down')),
      );

      await expectLater(forge.get(_url), throwsA(isA<ForgeOffline>()));
    });

    test('never puts the token in an error it throws', () async {
      // An error message is a place a token can escape to; assert it does not.
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((_) async => throw const SocketException('down')),
        token: const ForgeToken('ghp_secretvalue'),
      );

      Object? error;
      try {
        await forge.get(_url);
      } on ForgeError catch (e) {
        error = e;
      }

      expect(error, isNotNull);
      expect(error.toString(), isNot(contains('ghp_secretvalue')));
    });

    test('rejects a non-https URL without ever calling the client', () async {
      var calls = 0;
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((_) async {
          calls++;
          return _response('[]');
        }),
      );

      await expectLater(
        forge.get(Uri.parse('http://api.github.com/x')),
        throwsA(isA<ForgeMalformed>()),
      );
      expect(calls, 0);
    });

    test('disables redirects on the outgoing request', () async {
      late http.Request seen;
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((req) async {
          seen = req;
          return _response('[]');
        }),
      );

      await forge.get(_url);

      expect(seen.followRedirects, isFalse);
    });

    test('maps an unexpected redirect to ForgeMalformed', () async {
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient(
          (_) async =>
              _response('', status: 302, headers: {'location': 'elsewhere'}),
        ),
      );

      await expectLater(forge.get(_url), throwsA(isA<ForgeMalformed>()));
    });

    test('returns a 201 response rather than an error', () async {
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((_) async => _response('{}', status: 201)),
      );

      final res = await forge.get(_url);

      expect(res.status, 201);
    });

    test('returns a 204 response rather than an error', () async {
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((_) async => _response('', status: 204)),
      );

      final res = await forge.get(_url);

      expect(res.status, 204);
    });

    test('turns a timeout into ForgeOffline', () async {
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return _response('[]');
        }),
        timeout: Duration.zero,
      );

      await expectLater(forge.get(_url), throwsA(isA<ForgeOffline>()));
    });
  });

  group('per-host headers', () {
    test('a GitLab request authenticates with PRIVATE-TOKEN', () async {
      late Map<String, String> sent;
      final forge = ForgeHttp(
        kind: ForgeKind.gitlab,
        token: const ForgeToken('secret'),
        client: MockClient((req) async {
          sent = req.headers;
          return http.Response('{}', 200);
        }),
      );

      await forge.get(Uri.parse('https://gitlab.com/api/v4/projects/o%2Fr'));

      expect(sent['PRIVATE-TOKEN'], 'secret');
      // A bearer header would send the same token to whatever GitLab does
      // with it; only one scheme should ever be on the wire.
      expect(
        sent.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(sent['Accept'], 'application/json');
      expect(
        sent.keys.map((k) => k.toLowerCase()),
        isNot(contains('x-github-api-version')),
      );
    });

    test('a GitHub request still authenticates with a bearer token', () async {
      late Map<String, String> sent;
      final forge = ForgeHttp(
        kind: ForgeKind.github,
        token: const ForgeToken('secret'),
        client: MockClient((req) async {
          sent = req.headers;
          return http.Response('{}', 200);
        }),
      );

      await forge.get(Uri.parse('https://api.github.com/user'));

      expect(sent['Authorization'], 'Bearer secret');
      expect(sent['Accept'], 'application/vnd.github+json');
      expect(sent['X-GitHub-Api-Version'], '2022-11-28');
      expect(
        sent.keys.map((k) => k.toLowerCase()),
        isNot(contains('private-token')),
      );
    });

    test('an unauthenticated GitLab request sends no token header', () async {
      late Map<String, String> sent;
      final forge = ForgeHttp(
        kind: ForgeKind.gitlab,
        client: MockClient((req) async {
          sent = req.headers;
          return http.Response('{}', 200);
        }),
      );

      await forge.get(Uri.parse('https://gitlab.com/api/v4/projects/o%2Fr'));

      expect(
        sent.keys.map((k) => k.toLowerCase()),
        isNot(contains('private-token')),
      );
    });
  });
}
