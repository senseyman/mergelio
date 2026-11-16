import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/data/forge/github_parse.dart';
import 'package:mergelio/data/forge/github_forge.dart';
import 'package:mergelio/data/forge/gitlab_forge.dart';
import 'package:mergelio/data/forge/gitlab_parse.dart';
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

const _githubIssue = '''
{
  "number": 3,
  "title": "Crash on open",
  "state": "open",
  "body": "Steps\\n\\n1. open",
  "user": {"login": "ann"},
  "labels": [{"name": "bug"}],
  "updated_at": "2026-11-01T10:00:00Z"
}
''';

const _gitlabIssue = '''
{
  "iid": 3,
  "id": 991,
  "title": "Crash on open",
  "state": "closed",
  "description": "Steps",
  "author": {"username": "ann"},
  "labels": ["bug"]
}
''';

void main() {
  group('GitHub', () {
    test('reads one issue with its description', () async {
      late Uri called;
      final forge = github(
        MockClient((req) async {
          called = req.url;
          return http.Response(_githubIssue, 200);
        }),
      );

      final d = await forge.issue(3);

      expect(called.path, '/repos/o/r/issues/3');
      expect(d.issue.number, 3);
      expect(d.issue.title, 'Crash on open');
      expect(d.issue.state, IssueState.open);
      expect(d.issue.author.login, 'ann');
      expect(d.issue.labels, ['bug']);
      expect(d.body, 'Steps\n\n1. open');
    });

    test(
      'a pull request answered from the issues endpoint is malformed',
      () async {
        // GitHub serves pull requests from this endpoint too; one must never be
        // shown as if it were an issue.
        final forge = github(
          MockClient(
            (_) async => http.Response(
              _githubIssue.replaceFirst(
                '"number": 3,',
                '"number": 3, "pull_request": {},',
              ),
              200,
            ),
          ),
        );

        await expectLater(forge.issue(3), throwsA(isA<ForgeMalformed>()));
      },
    );

    test('an issue with no body reads as empty', () async {
      final forge = github(
        MockClient(
          (_) async => http.Response(
            _githubIssue.replaceFirst('"Steps\\n\\n1. open"', 'null'),
            200,
          ),
        ),
      );

      expect((await forge.issue(3)).body, '');
    });

    test('an answer about a different issue is malformed', () async {
      final forge = github(
        MockClient(
          (_) async => http.Response(
            _githubIssue.replaceFirst('"number": 3', '"number": 4'),
            200,
          ),
        ),
      );

      await expectLater(forge.issue(3), throwsA(isA<ForgeMalformed>()));
    });

    test('an issue the token cannot see is reported, not hidden', () async {
      final forge = github(MockClient((_) async => http.Response('', 404)));

      await expectLater(forge.issue(3), throwsA(isA<ForgeError>()));
    });

    test('refuses a number no forge hands out', () async {
      final forge = github(
        MockClient((_) async => fail('nothing should be requested')),
      );

      expect(() => forge.issue(0), throwsArgumentError);
    });

    test('a body lacking what an issue needs parses as nothing', () {
      expect(parseIssueDetail(<String, Object?>{}), isNull);
    });
  });

  group('GitLab', () {
    test('reads one issue by iid with its description', () async {
      late Uri called;
      final forge = gitlab(
        MockClient((req) async {
          called = req.url;
          return http.Response(_gitlabIssue, 200);
        }),
      );

      final d = await forge.issue(3);

      expect(
        called.toString(),
        startsWith(
          'https://gitlab.com/api/v4/projects/group%2Fsub%2Fapp/issues/3',
        ),
      );
      expect(d.issue.number, 3);
      expect(d.issue.state, IssueState.closed);
      expect(d.body, 'Steps');
    });

    test('an answer about a different issue is malformed', () async {
      final forge = gitlab(
        MockClient(
          (_) async => http.Response(
            _gitlabIssue.replaceFirst('"iid": 3', '"iid": 4'),
            200,
          ),
        ),
      );

      await expectLater(forge.issue(3), throwsA(isA<ForgeMalformed>()));
    });

    test('refuses a number no forge hands out', () async {
      final forge = gitlab(
        MockClient((_) async => fail('nothing should be requested')),
      );

      expect(() => forge.issue(-1), throwsArgumentError);
    });

    test('a null description parses as empty', () {
      final d = parseGitlabIssueDetail(<String, Object?>{
        'iid': 3,
        'title': 't',
        'state': 'opened',
        'description': null,
      });
      expect(d?.body, '');
    });
  });
}
