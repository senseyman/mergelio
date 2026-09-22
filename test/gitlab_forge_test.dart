import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/data/forge/github_forge.dart';
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
    // 'deploy' is the fixture's untriggered manual job, which carries no
    // result and so produces no run.
    expect(summary.runs.map((r) => r.name), containsAll(['build', 'lint']));
    expect(summary.runs.map((r) => r.name), isNot(contains('deploy')));
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

  test('does not follow a next link that names another host', () async {
    // The Link header is chosen by whatever answered the request. Following
    // it to a host this call never resolved would send the user's GitLab
    // token to that host; paging simply ends instead.
    final hosts = <String>[];
    final forge = forgeWith(
      MockClient((req) async {
        hosts.add(req.url.host);
        return http.Response(
          fixture('merge_requests.json'),
          200,
          headers: {
            'link':
                '<https://api.github.com/repos/o/r/pulls?page=2>; rel="next"',
          },
        );
      }),
    );

    final prs = await forge.pullRequests(limit: 50);

    expect(hosts, ['gitlab.com']);
    // Ending paging is not an error: the rows already in hand are returned.
    expect(prs.map((p) => p.number), [42, 43]);
  });

  test('stops paging at the cap rather than following forever', () async {
    // A project with thousands of open requests must not spend a whole
    // session's budget filling one sidebar section.
    var calls = 0;
    final forge = GitlabForge(
      host: _host,
      http: ForgeHttp(
        kind: ForgeKind.gitlab,
        client: MockClient((_) async {
          calls++;
          return http.Response(
            '[]',
            200,
            headers: {
              'link':
                  '<https://gitlab.com/api/v4/projects/group%2Fsub%2Fapp'
                  '/merge_requests?page=99>; rel="next"',
            },
          );
        }),
      ),
      maxPages: 3,
    );

    await forge.pullRequests();

    expect(calls, 3);
  });

  test('reuses one cache across calls, so a 304 is served locally', () async {
    var bodies = 0;
    final forge = forgeWith(
      MockClient((req) async {
        if (req.headers['if-none-match'] != null) {
          return http.Response('', 304);
        }
        bodies++;
        return http.Response(
          fixture('issues.json'),
          200,
          headers: {'etag': 'W/"a"'},
        );
      }),
    );

    final first = await forge.issues();
    final second = await forge.issues();

    expect(bodies, 1, reason: 'the second call must revalidate, not refetch');
    expect(second.map((i) => i.number), first.map((i) => i.number));
    expect(second, isNotEmpty, reason: 'the cached body must be reused');
  });

  group('says the same thing as the GitHub forge for the same failure', () {
    // Both forges raise ForgeMalformed for these three conditions. Two
    // spellings of one condition read like two different conditions, and
    // the detail is what toString() echoes, so it is the only thing a
    // reader has to go on.
    GitHubForge githubWith(MockClient client) => GitHubForge(
      host: const ForgeHost(
        kind: ForgeKind.github,
        host: 'github.com',
        owner: 'o',
        repo: 'r',
      ),
      http: ForgeHttp(kind: ForgeKind.github, client: client),
    );

    Future<String> detailOf(Future<Object?> call) async {
      try {
        await call;
      } on ForgeMalformed catch (e) {
        return e.detail;
      }
      fail('expected a ForgeMalformed');
    }

    test('a body that is not json', () async {
      MockClient client() =>
          MockClient((_) async => http.Response('<html>', 200));

      expect(
        await detailOf(forgeWith(client()).pullRequests()),
        await detailOf(githubWith(client()).pullRequests()),
      );
    });

    test('a ref that cannot be put in a url', () async {
      MockClient client() => MockClient((_) async => http.Response('[]', 200));

      expect(
        await detailOf(forgeWith(client()).checksForRef('..')),
        await detailOf(githubWith(client()).checksForRef('..')),
      );
    });

    test('a 304 with nothing cached to serve', () async {
      // A validator is the only thing that can produce a 304, so an empty
      // cache here means it went missing mid-flight.
      MockClient client() => MockClient((_) async => http.Response('', 304));

      expect(
        await detailOf(forgeWith(client()).pullRequests()),
        await detailOf(githubWith(client()).pullRequests()),
      );
    });
  });
}
