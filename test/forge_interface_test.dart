import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';

import 'support/fake_forge.dart';

void main() {
  const host = ForgeHost(
    kind: ForgeKind.github,
    host: 'github.com',
    owner: 'owner',
    repo: 'repo',
  );

  test('a fake forge satisfies the interface it is given', () async {
    const pr = PullRequest(
      number: 7,
      title: 'Fix thing',
      state: PullRequestState.open,
      author: ForgeUser(login: 'octocat'),
      sourceBranch: 'fix/thing',
      targetBranch: 'main',
      headSha: 'abc123',
    );
    const issue = Issue(
      number: 3,
      title: 'Thing is broken',
      state: IssueState.open,
      author: ForgeUser(login: 'octocat'),
    );

    final Forge forge = FakeForge(
      host: host,
      pullRequests: [pr],
      issues: [issue],
    );

    expect(forge.host, host);
    expect(await forge.pullRequests(), [pr]);
    expect(await forge.pullRequestsForBranch('fix/thing'), [pr]);
    expect(await forge.pullRequestsForBranch('other'), isEmpty);
    expect((await forge.checksForRef('abc123')).overall, ChecksOverall.none);
    expect(await forge.issues(), [issue]);
  });

  test('an error armed on one method does not leak into another', () async {
    final Forge forge = FakeForge(
      host: host,
      pullRequestsError: const ForgeUnauthenticated(),
    );

    await expectLater(
      forge.pullRequests(),
      throwsA(isA<ForgeUnauthenticated>()),
    );
    expect(await forge.issues(), isEmpty);
  });

  test(
    'an error armed on pullRequestsForBranch does not break pullRequests',
    () async {
      final Forge forge = FakeForge(
        host: host,
        pullRequestsForBranchError: const ForgeUnauthenticated(),
      );

      await expectLater(
        forge.pullRequestsForBranch('fix/thing'),
        throwsA(isA<ForgeUnauthenticated>()),
      );
      expect(await forge.pullRequests(), isEmpty);
    },
  );

  test('every call is counted, per method', () async {
    final forge = FakeForge(host: host);

    await forge.pullRequests();
    await forge.pullRequests();
    await forge.pullRequestsForBranch('fix/thing');
    await forge.issues();

    expect(forge.pullRequestsCalls, 2);
    expect(forge.pullRequestsForBranchCalls, 1);
    expect(forge.issuesCalls, 1);
  });

  test('checksForRef records which ref was asked about', () async {
    final forge = FakeForge(host: host);

    await forge.checksForRef('abc123');
    await forge.checksForRef('def456');

    expect(forge.checkedRefs, ['abc123', 'def456']);
    expect(forge.checksCalls, 2);
  });
}
