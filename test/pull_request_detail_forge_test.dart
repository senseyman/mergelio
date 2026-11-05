import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/data/forge/github_forge.dart';
import 'package:mergelio/data/forge/gitlab_forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';

const _github = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

const _gitlab = ForgeHost(
  kind: ForgeKind.gitlab,
  host: 'gitlab.com',
  owner: 'group/sub',
  repo: 'app',
);

GitHubForge github(MockClient client) => GitHubForge(
  host: _github,
  http: ForgeHttp(kind: ForgeKind.github, client: client),
);

GitlabForge gitlab(MockClient client) => GitlabForge(
  host: _gitlab,
  http: ForgeHttp(kind: ForgeKind.gitlab, client: client),
);

const _githubPull = '''
{
  "number": 7,
  "title": "Add the thing",
  "state": "open",
  "draft": false,
  "body": "## Why\\n\\nBecause.",
  "user": {"login": "ann"},
  "head": {"ref": "feature/x", "sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
  "base": {"ref": "main", "sha": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
  "updated_at": "2026-11-01T10:00:00Z"
}
''';

const _gitlabMr = '''
{
  "iid": 7,
  "id": 991,
  "title": "Add the thing",
  "state": "opened",
  "description": "Closes #3",
  "author": {"username": "ann"},
  "source_branch": "feature/x",
  "target_branch": "main",
  "sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
''';

void main() {
  group('GitHub', () {
    test('reads one pull request with its description', () async {
      late Uri called;
      final forge = github(
        MockClient((req) async {
          called = req.url;
          return http.Response(_githubPull, 200);
        }),
      );

      final d = await forge.pullRequest(7);

      expect(called.path, '/repos/o/r/pulls/7');
      expect(d.request.number, 7);
      expect(d.request.title, 'Add the thing');
      expect(d.request.sourceBranch, 'feature/x');
      expect(d.request.targetBranch, 'main');
      expect(d.request.headSha, 'a' * 40);
      expect(d.request.author.login, 'ann');
      expect(d.body, '## Why\n\nBecause.');
    });

    test('a request with no description reads as an empty body', () async {
      // GitHub sends null, not an empty string, when nothing was written.
      final forge = github(
        MockClient(
          (_) async => http.Response(
            _githubPull.replaceFirst('"## Why\\n\\nBecause."', 'null'),
            200,
          ),
        ),
      );

      expect((await forge.pullRequest(7)).body, '');
    });

    test('a body missing what a request needs is malformed', () async {
      final forge = github(
        MockClient((_) async => http.Response('{"number": 7}', 200)),
      );

      await expectLater(forge.pullRequest(7), throwsA(isA<ForgeMalformed>()));
    });

    test('an answer about a different request is malformed', () async {
      // The number decides which ref is fetched and which page a link opens,
      // so a reply that names another request cannot stand in for this one.
      final forge = github(
        MockClient(
          (_) async => http.Response(
            _githubPull.replaceFirst('"number": 7', '"number": 8'),
            200,
          ),
        ),
      );

      await expectLater(forge.pullRequest(7), throwsA(isA<ForgeMalformed>()));
    });

    test('a request the token cannot see is reported, not hidden', () async {
      // Unlike CI, the request is the whole point of the view: there is no
      // smaller thing left to show without it.
      final forge = github(MockClient((_) async => http.Response('', 404)));

      await expectLater(forge.pullRequest(7), throwsA(isA<ForgeNotVisible>()));
    });

    test('refuses a number no forge hands out', () async {
      final forge = github(
        MockClient((_) async => fail('nothing should be requested')),
      );

      expect(() => forge.pullRequest(0), throwsArgumentError);
    });
  });

  group('GitLab', () {
    test('reads one merge request by iid with its description', () async {
      late Uri called;
      final forge = gitlab(
        MockClient((req) async {
          called = req.url;
          return http.Response(_gitlabMr, 200);
        }),
      );

      final d = await forge.pullRequest(7);

      expect(
        called.toString(),
        startsWith(
          'https://gitlab.com/api/v4/projects/group%2Fsub%2Fapp/merge_requests/7',
        ),
      );
      expect(d.request.number, 7);
      expect(d.request.targetBranch, 'main');
      expect(d.body, 'Closes #3');
    });

    test('an answer about a different request is malformed', () async {
      final forge = gitlab(
        MockClient(
          (_) async => http.Response(
            _gitlabMr.replaceFirst('"iid": 7', '"iid": 8'),
            200,
          ),
        ),
      );

      await expectLater(forge.pullRequest(7), throwsA(isA<ForgeMalformed>()));
    });

    test('refuses a number no forge hands out', () async {
      final forge = gitlab(
        MockClient((_) async => fail('nothing should be requested')),
      );

      expect(() => forge.pullRequest(-1), throwsArgumentError);
    });
  });

  test('a detail compares by value', () {
    const pr = PullRequest(
      number: 1,
      title: 't',
      state: PullRequestState.open,
      author: ForgeUser(login: 'a'),
      sourceBranch: 's',
      targetBranch: 'm',
      headSha: 'h',
    );
    expect(
      const PullRequestDetail(request: pr, body: 'b'),
      const PullRequestDetail(request: pr, body: 'b'),
    );
  });
}
