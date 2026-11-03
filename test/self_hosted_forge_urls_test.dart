import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/data/forge/github_forge.dart';
import 'package:mergelio/data/forge/gitlab_forge.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';

const _ghe = ForgeHost(
  kind: ForgeKind.github,
  host: 'ghe.corp',
  port: 8443,
  owner: 'o',
  repo: 'r',
);

const _gitlab = ForgeHost(
  kind: ForgeKind.gitlab,
  host: 'git.corp',
  owner: 'group/sub',
  repo: 'app',
);

/// Records every URL a forge asks for and answers with an empty list.
(MockClient, List<Uri>) _recording() {
  final calls = <Uri>[];
  return (
    MockClient((req) async {
      calls.add(req.url);
      return http.Response('[]', 200);
    }),
    calls,
  );
}

void main() {
  test('github enterprise reads from its own /api/v3, port included', () async {
    final (client, calls) = _recording();
    final forge = GitHubForge(
      host: _ghe,
      http: ForgeHttp(kind: ForgeKind.github, client: client),
    );

    await forge.pullRequests();

    expect(calls, isNotEmpty);
    for (final url in calls) {
      expect(url.host, 'ghe.corp');
      expect(url.port, 8443);
      expect(url.path, startsWith('/api/v3/repos/o/r/'));
    }
  });

  test('self-managed gitlab reads from its own /api/v4', () async {
    final (client, calls) = _recording();
    final forge = GitlabForge(
      host: _gitlab,
      http: ForgeHttp(kind: ForgeKind.gitlab, client: client),
    );

    await forge.pullRequests();

    expect(
      calls.first.toString(),
      startsWith(
        'https://git.corp/api/v4/projects/group%2Fsub%2Fapp/merge_requests',
      ),
    );
  });

  test('browser links go to the installation, port included', () {
    expect(
      pullRequestWebUrl(_ghe, 3).toString(),
      'https://ghe.corp:8443/o/r/pull/3',
    );
    expect(
      issueWebUrl(_gitlab, 4).toString(),
      'https://git.corp/group/sub/app/-/issues/4',
    );
    expect(
      newPullRequestWebUrl(_ghe, 'x')!.toString(),
      'https://ghe.corp:8443/o/r/compare/x?expand=1',
    );
    expect(
      newPullRequestWebUrl(_gitlab, 'x')!.path,
      '/group/sub/app/-/merge_requests/new',
    );
    expect(newPullRequestWebUrl(_gitlab, 'x')!.host, 'git.corp');
  });
}
