import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/state/forge.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

Issue _issue(int n, {List<String> labels = const []}) => Issue(
  number: n,
  title: 'issue $n',
  state: IssueState.open,
  author: const ForgeUser(login: 'me'),
  labels: labels,
);

class _FakeForge implements Forge {
  @override
  final ForgeHost host = _host;

  final List<Issue> result;
  final ForgeError? failWith;
  int sawLimit = 0;

  _FakeForge({this.result = const [], this.failWith});

  @override
  Future<List<Issue>> issues({int limit = 50}) async {
    sawLimit = limit;
    if (failWith != null) throw failWith!;
    return result.take(limit).toList(growable: false);
  }

  @override
  Future<List<PullRequest>> pullRequests({int limit = 50}) async => [];

  @override
  Future<List<PullRequest>> pullRequestsForBranch(
    String branch, {
    int limit = 50,
  }) async => [];

  @override
  Future<ChecksSummary> checksForRef(String ref) async =>
      const ChecksSummary(overall: ChecksOverall.none);
}

ProviderContainer _containerFor(Forge? forge) {
  final c = ProviderContainer(
    overrides: [githubForgeProvider.overrideWith((ref, path) async => forge)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('issuePanelProvider', () {
    test(
      'returns an empty list when the repository is not on a forge',
      () async {
        final issues = await _containerFor(null)
            .read(issuePanelProvider('/repo').future);
        expect(issues, isEmpty);
      },
    );

    test('returns the issues the forge answers with', () async {
      final forge = _FakeForge(result: [_issue(1), _issue(2)]);
      final issues = await _containerFor(forge)
          .read(issuePanelProvider('/repo').future);
      expect(issues.map((i) => i.number), [1, 2]);
    });

    test('asks for the same budgeted row count pull requests use', () async {
      final forge = _FakeForge();
      await _containerFor(forge).read(issuePanelProvider('/repo').future);
      expect(forge.sawLimit, kPullRequestLimit);
    });

    test('a failed read reaches the caller, never an empty list', () async {
      final forge = _FakeForge(failWith: const ForgeUnauthenticated());
      await expectLater(
        _containerFor(forge).read(issuePanelProvider('/repo').future),
        throwsA(isA<ForgeUnauthenticated>()),
      );
    });
  });
}
