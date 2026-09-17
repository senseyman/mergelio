import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/data/forge/github_forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

String fixture(String name) =>
    File('test/fixtures/forge/github/$name').readAsStringSync();

GitHubForge forgeWith(MockClient client) => GitHubForge(
  host: _host,
  http: ForgeHttp(client: client),
);

void main() {
  test('pullRequests calls the repository pulls endpoint', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response(fixture('pulls.json'), 200);
      }),
    );

    final prs = await forge.pullRequests();

    expect(called.host, 'api.github.com');
    expect(called.path, '/repos/o/r/pulls');
    expect(called.queryParameters['state'], 'open');
    expect(prs, hasLength(4));
  });

  test('asks for a full page, so the page cap is worth something', () async {
    // The cap on pages only bounds the work if each page is large. Dropping
    // per_page would silently turn 5 pages of 100 into 5 pages of 30.
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response('[]', 200);
      }),
    );

    await forge.pullRequests();

    expect(called.queryParameters['per_page'], '100');
  });

  test('pullRequestsForBranch asks the API to filter by head', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response('[]', 200);
      }),
    );

    await forge.pullRequestsForBranch('fix/thing');

    // The head filter is owner-qualified; without the owner prefix GitHub
    // ignores it and returns every open request.
    expect(called.queryParameters['head'], 'o:fix/thing');
  });

  test('checksForRef merges both CI endpoints', () async {
    final paths = <String>[];
    final forge = forgeWith(
      MockClient((req) async {
        paths.add(req.url.path);
        return http.Response(
          req.url.path.endsWith('/status')
              ? fixture('status_combined.json')
              : fixture('check_runs.json'),
          200,
        );
      }),
    );

    final summary = await forge.checksForRef('abc123');

    expect(paths, contains('/repos/o/r/commits/abc123/status'));
    expect(paths, contains('/repos/o/r/commits/abc123/check-runs'));
    expect(summary.runs, hasLength(7));
    expect(summary.overall, ChecksOverall.failure);
  });

  test('checksForRef refuses a ref that would walk out of the repo', () async {
    // The ref lands in the URL path, and Uri resolves `..` away, so an
    // unchecked ref addresses a different repository under the same token.
    // Git forbids `..` in a ref, so refusing loses nothing real.
    var called = false;
    final forge = forgeWith(
      MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    for (final ref in [
      '../../other/repo/commits/x',
      '..',
      'a/../../b',
      '',
      'has space',
      'a?b',
      'a#b',
    ]) {
      await expectLater(
        forge.checksForRef(ref),
        throwsA(isA<ForgeMalformed>()),
        reason: 'ref "$ref" must not reach the network',
      );
    }
    expect(called, isFalse, reason: 'nothing may be requested for a bad ref');
  });

  test('checksForRef keeps a branch name that contains slashes', () async {
    // A branch ref legitimately contains `/`, and GitHub wants those slashes
    // literal in the path. Percent-encoding them would 404 every nested
    // branch, so the guard must reject traversal without escaping slashes.
    final paths = <String>[];
    final forge = forgeWith(
      MockClient((req) async {
        paths.add(req.url.path);
        return http.Response('{}', 200);
      }),
    );

    await forge.checksForRef('feature/nested/thing');

    expect(paths, contains('/repos/o/r/commits/feature/nested/thing/status'));
  });

  test('checksForRef reports none when neither endpoint is visible', () async {
    // A repository with no CI, or a token that cannot see it, is not an error
    // — the badge simply has nothing to show.
    final forge = forgeWith(MockClient((_) async => http.Response('', 404)));

    expect((await forge.checksForRef('abc123')).overall, ChecksOverall.none);
  });

  test('checksForRef still reports an expired token', () async {
    // Only "not visible" means "not configured". Swallowing an auth failure
    // here would show a repository as having no CI when the real answer is
    // that nobody is signed in.
    final forge = forgeWith(MockClient((_) async => http.Response('', 401)));

    await expectLater(
      forge.checksForRef('abc123'),
      throwsA(isA<ForgeUnauthenticated>()),
    );
  });

  test('issues calls the issues endpoint and excludes pull requests', () async {
    late Uri called;
    final forge = forgeWith(
      MockClient((req) async {
        called = req.url;
        return http.Response(fixture('issues.json'), 200);
      }),
    );

    final issues = await forge.issues();

    expect(called.path, '/repos/o/r/issues');
    expect(issues.map((i) => i.number), [12, 3]);
  });

  test('follows the next link until it runs out', () async {
    var calls = 0;
    final forge = forgeWith(
      MockClient((req) async {
        calls++;
        final first = req.url.queryParameters['page'] == null;
        return http.Response(
          first ? fixture('pulls.json') : '[]',
          200,
          headers: first
              ? {
                  'link': '<https://api.github.com/repos/o/r/pulls?page=2>; rel="next"',
                }
              : const {},
        );
      }),
    );

    await forge.pullRequests();

    expect(calls, 2);
  });

  test('keeps the items from every page it read', () async {
    // Counting the calls proves it paged; only the results prove it kept what
    // paging cost. A later page that overwrote the earlier one would page
    // just as eagerly and still lose the rows.
    final forge = forgeWith(
      MockClient((req) async {
        final first = req.url.queryParameters['page'] == null;
        return http.Response(
          first
              ? fixture('pulls.json')
              : '[{"number": 99, "title": "page two", "state": "open", '
                    '"head": {"ref": "b", "sha": "s"}, "base": {"ref": "main"}}]',
          200,
          headers: first
              ? {
                  'link': '<https://api.github.com/repos/o/r/pulls?page=2>; rel="next"',
                }
              : const {},
        );
      }),
    );

    final prs = await forge.pullRequests();

    expect(prs, hasLength(5));
    expect(prs.map((p) => p.number), containsAll([7, 99]));
  });

  test('stops paging at the cap rather than following forever', () async {
    // A repository with thousands of open items must not spend the whole rate
    // limit filling one sidebar section.
    var calls = 0;
    final forge = GitHubForge(
      host: _host,
      http: ForgeHttp(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            '[]',
            200,
            headers: {
              'link': '<https://api.github.com/repos/o/r/pulls?page=99>; rel="next"',
            },
          );
        }),
      ),
      maxPages: 3,
    );

    await forge.pullRequests();

    expect(calls, 3);
  });

  test('caps results at limit even when the API returned more', () async {
    final forge = forgeWith(
      MockClient((_) async => http.Response(fixture('pulls.json'), 200)),
    );

    expect(await forge.pullRequests(limit: 2), hasLength(2));
  });

  test('caps issues at limit too', () async {
    final forge = forgeWith(
      MockClient((_) async => http.Response(fixture('issues.json'), 200)),
    );

    expect(await forge.issues(limit: 1), hasLength(1));
  });

  test('lets an auth failure reach the caller', () async {
    // The state layer decides what an expired token means for the UI; the
    // forge must not swallow it into an empty list.
    final forge = forgeWith(MockClient((_) async => http.Response('', 401)));

    await expectLater(
      forge.pullRequests(),
      throwsA(isA<ForgeUnauthenticated>()),
    );
  });

  test('turns an unreadable body into ForgeMalformed', () async {
    final forge = forgeWith(
      MockClient((_) async => http.Response('not json at all', 200)),
    );

    await expectLater(forge.pullRequests(), throwsA(isA<ForgeMalformed>()));
  });

  test('a body that is not a list reads as no rows', () async {
    // An object where a list belongs is a shape this version does not know.
    // It is not a crash, and it is not data either.
    final forge = forgeWith(
      MockClient((_) async => http.Response('{"message": "nope"}', 200)),
    );

    expect(await forge.pullRequests(), isEmpty);
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
  });
}
