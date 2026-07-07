import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/repo_data.dart';

/// Verifies the provider wiring end to end against a real repository: every ref
/// list is populated and lane layout is applied to the commits (which the raw
/// reader does not do — proving the provider ran [assignLanes]).
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> write(String name, String content) =>
      File('${dir.path}/$name').writeAsString(content);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_provider_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);

    await write('a.txt', '1\n');
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'A']);

    await g(['checkout', '-q', '-b', 'feature']);
    await write('b.txt', 'b\n');
    await g(['add', 'b.txt']);
    await g(['commit', '-q', '-m', 'B on feature']);

    await g(['checkout', '-q', 'main']);
    await write('a.txt', '2\n');
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'C on main']);

    await g(['merge', '--no-ff', '-m', 'Merge feature', 'feature']);
    await g(['tag', 'v1.0']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('loads all ref lists and applies lane layout to commits', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final data = await container.read(repoDataProvider(dir.path).future);

    expect(data.commits, isNotEmpty);
    expect(data.commits.any((c) => c.merge), isTrue);
    // Raw commits leave lane at 0; the feature branch forces a second lane, so
    // a non-zero lane proves assignLanes ran inside the provider.
    expect(data.commits.any((c) => c.lane > 0), isTrue);
    expect(data.branches.map((b) => b.name), containsAll(['main', 'feature']));
    expect(data.tags, contains('v1.0'));

    // Branch colour is wired to the tip commit's lane (assignBranchColors ran):
    // main's tip carries a local 'main' ref, and its ci must match the branch.
    final mainTip = data.commits.firstWhere(
      (c) => c.refs.any((r) => r.kind == RefKind.local && r.name == 'main'),
    );
    expect(data.branches.firstWhere((b) => b.name == 'main').ci, mainTip.ci);
  });

  test('exposes squash links from the provider', () async {
    // Squash-merge feature onto main so a link is inferred.
    await g(['checkout', '-q', '-b', 'squashme', 'main']);
    await write('s.txt', 's\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'squash work']);
    await g(['checkout', '-q', 'main']);
    await g(['merge', '--squash', 'squashme']);
    await g(['commit', '-q', '-m', 'Squash (#9)']);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final data = await container.read(repoDataProvider(dir.path).future);

    final squashTip = (await svc.run([
      'rev-parse',
      'squashme',
    ], repoPath: dir.path)).out;
    expect(data.squashLinks.map((l) => l.fromSha), contains(squashTip));
  });

  test('commitFilesProvider lists a commit\'s changed files', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final data = await container.read(repoDataProvider(dir.path).future);
    final root = data.commits.firstWhere((c) => c.parents.isEmpty);
    final files = await container.read(
      commitFilesProvider((repo: dir.path, sha: root.sha)).future,
    );
    expect(files.single.path, 'a.txt');
    expect(files.single.change, GitChange.added);
  });

  test('surfaces an error for a non-repository path', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
      container.read(repoDataProvider('/no/such/mergelio-xyz').future),
      throwsA(isA<GitException>()),
    );
  });
}
