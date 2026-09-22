import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/data/forge/gitlab_forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';

const _host = ForgeHost(
  kind: ForgeKind.gitlab,
  host: 'gitlab.com',
  owner: 'group/sub',
  repo: 'app',
);

String fixture(String name) =>
    File('test/fixtures/forge/gitlab/$name').readAsStringSync();

GitlabForge forgeWith(MockClient client) => GitlabForge(
  host: _host,
  http: ForgeHttp(kind: ForgeKind.gitlab, client: client),
);

void main() {
  test('addresses a nested group by encoded project path', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response(fixture('merge_requests.json'), 200);
      }),
    );

    await forge.pullRequests();

    // The whole path is one path segment, so its slashes are escaped. A
    // request built with Uri.https would double-encode the percent sign and
    // one built from pathSegments would unescape the slashes back into
    // separators; both address a project that does not exist.
    expect(
      called.toString(),
      startsWith(
        'https://gitlab.com/api/v4/projects/group%2Fsub%2Fapp/merge_requests',
      ),
    );
    expect(called.toString(), isNot(contains('%252F')));
  });

  test('asks only for open requests, newest first', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response(fixture('merge_requests.json'), 200);
      }),
    );

    await forge.pullRequests();

    expect(called.queryParameters['state'], 'opened');
    expect(called.queryParameters['order_by'], 'updated_at');
    expect(called.queryParameters['sort'], 'desc');
  });

  test('reads merge requests into rows', () async {
    final forge = forgeWith(
      MockClient(
        (_) async => http.Response(fixture('merge_requests.json'), 200),
      ),
    );

    final prs = await forge.pullRequests();

    expect(prs.map((p) => p.number), [42, 43]);
  });

  test('honours the row limit', () async {
    final forge = forgeWith(
      MockClient(
        (_) async => http.Response(fixture('merge_requests.json'), 200),
      ),
    );

    expect((await forge.pullRequests(limit: 1)).length, 1);
  });

  test('filters by source branch without qualifying it', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response('[]', 200);
      }),
    );

    await forge.pullRequestsForBranch('feat/graph');

    // GitLab matches the branch name as sent; qualifying it the way GitHub
    // requires would match nothing at all.
    expect(called.queryParameters['source_branch'], 'feat/graph');
  });

  test('follows the Link header to the next page', () async {
    var calls = 0;
    final forge = forgeWith(
      MockClient((req) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            fixture('merge_requests.json'),
            200,
            headers: {
              'link': '<https://gitlab.com/api/v4/projects/group%2Fsub%2Fapp/merge_requests?page=2>; rel="next"',
            },
          );
        }
        return http.Response('[]', 200);
      }),
    );

    await forge.pullRequests(limit: 50);

    expect(calls, 2);
  });

  test('reads CI from the commit statuses endpoint', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response(fixture('statuses.json'), 200);
      }),
    );

    final summary = await forge.checksForRef('abc123');

    expect(
      called.path,
      '/api/v4/projects/group%2Fsub%2Fapp/repository/commits/abc123/statuses',
    );
    expect(
      summary.runs.map((r) => r.name),
      containsAll(['build', 'lint', 'deploy']),
    );
  });

  test('escapes a branch name used as a ref', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response('[]', 200);
      }),
    );

    await forge.checksForRef('feat/graph');

    expect(called.toString(), contains('commits/feat%2Fgraph/statuses'));
  });

  test('refuses a ref that could rewrite the request path', () async {
    var called = false;
    final forge = forgeWith(
      MockClient((_) async {
        called = true;
        return http.Response('[]', 200);
      }),
    );

    await expectLater(forge.checksForRef('..'), throwsA(isA<ForgeMalformed>()));
    // Refused before the request, not after: the point is that it never
    // reaches the network under the user's token.
    expect(called, isFalse);
  });

  test(
    'a commit the token cannot see reports no CI rather than failing',
    () async {
      final forge = forgeWith(MockClient((_) async => http.Response('', 404)));

      expect((await forge.checksForRef('abc123')).overall, ChecksOverall.none);
    },
  );

  test('a project with issues switched off reads as empty', () async {
    // GitLab answers 403 (feature disabled) or 404 rather than GitHub's 410.
    for (final status in [403, 404]) {
      final forge = forgeWith(
        MockClient((_) async => http.Response('', status)),
      );

      expect(await forge.issues(), isEmpty, reason: 'status $status');
    }
  });

  test('a genuine server fault on issues still reaches the caller', () async {
    final forge = forgeWith(MockClient((_) async => http.Response('', 503)));

    await expectLater(forge.issues(), throwsA(isA<ForgeServerFault>()));
  });

  test('an expired token still surfaces as unauthenticated', () async {
    final forge = forgeWith(MockClient((_) async => http.Response('', 401)));

    await expectLater(
      forge.pullRequests(),
      throwsA(isA<ForgeUnauthenticated>()),
    );
  });

  test('reads the project default branch', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response(fixture('project.json'), 200);
      }),
    );

    expect(await forge.defaultBranch(), 'trunk');
    expect(called.path, '/api/v4/projects/group%2Fsub%2Fapp');
  });

  test('a project that names no default branch reads as null', () async {
    final forge = forgeWith(MockClient((_) async => http.Response('{}', 200)));

    expect(await forge.defaultBranch(), isNull);
  });

  test('a body that is not JSON reads as malformed', () async {
    final forge = forgeWith(
      MockClient((_) async => http.Response('<html>', 200)),
    );

    await expectLater(forge.pullRequests(), throwsA(isA<ForgeMalformed>()));
  });
}
