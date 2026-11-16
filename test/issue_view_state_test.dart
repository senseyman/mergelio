import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/issue_view.dart';

import 'support/fake_forge.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

const _detail = IssueDetail(
  issue: Issue(
    number: 3,
    title: 'Crash on open',
    state: IssueState.open,
    author: ForgeUser(login: 'ann'),
  ),
  body: 'Steps',
);

const IssueTarget _target = (repoPath: '/repo', number: 3);

ProviderContainer _container(FakeForge? forge) {
  final c = ProviderContainer(
    overrides: [forgeProvider.overrideWith((ref, path) async => forge)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('nothing is open to begin with', () {
    expect(_container(null).read(issueTargetProvider), isNull);
  });

  test('reads the issue the target names', () async {
    final forge = FakeForge(host: _host, issueDetails: {3: _detail});
    final c = _container(forge);

    expect(await c.read(issueDetailProvider(_target).future), _detail);
    expect(forge.issueCalls, 1);
  });

  test('a repository off any forge reads as null', () async {
    final c = _container(null);

    expect(await c.read(issueDetailProvider(_target).future), isNull);
  });

  test('a second read while listened is not a second request', () async {
    final forge = FakeForge(host: _host, issueDetails: {3: _detail});
    final c = _container(forge);
    c.listen(issueDetailProvider(_target), (_, _) {});

    await c.read(issueDetailProvider(_target).future);
    await c.read(issueDetailProvider(_target).future);

    expect(forge.issueCalls, 1);
  });

  test('a failure reaches the caller', () async {
    final forge = FakeForge(host: _host, issueError: const ForgeNotVisible());
    final c = _container(forge);
    c.listen(issueDetailProvider(_target), (_, _) {});

    await expectLater(
      c.read(issueDetailProvider(_target).future),
      throwsA(isA<ForgeNotVisible>()),
    );
  });
}
