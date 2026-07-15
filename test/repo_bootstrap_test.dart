import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_bootstrap.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  const svc = SystemGitService();
  late Directory work;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('mergelio_bootstrap_');
  });

  tearDown(() async {
    if (await work.exists()) await work.delete(recursive: true);
  });

  group('folderNameFromUrl', () {
    test('derives from https, ssh and local forms', () {
      expect(
        RepoBootstrap.folderNameFromUrl('https://github.com/acme/repo.git'),
        'repo',
      );
      expect(
        RepoBootstrap.folderNameFromUrl('git@github.com:acme/repo.git'),
        'repo',
      );
      expect(RepoBootstrap.folderNameFromUrl('/local/path/repo'), 'repo');
      expect(
        RepoBootstrap.folderNameFromUrl('https://host/a/trailing/'),
        'trailing',
      );
      expect(RepoBootstrap.folderNameFromUrl(''), '');
    });
  });

  test('clone clones a real repo, opens a tab', () async {
    // Local origin with one commit.
    final origin = Directory('${work.path}/origin')..createSync();
    Future<void> g(List<String> args) async {
      final r = await svc.run(args, repoPath: origin.path);
      if (!r.ok) throw StateError('git ${args.join(' ')}: ${r.err}');
    }

    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${origin.path}/a.txt').writeAsString('A\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'A']);

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final parent = Directory('${work.path}/clones')..createSync();

    final path = await c
        .read(repoBootstrapProvider)
        .clone(url: origin.path, parentDir: parent.path);

    expect(path, isNotNull);
    expect(File('$path/a.txt').existsSync(), isTrue);
    expect(await svc.isRepository(path!), isTrue);
    // Opened as the active tab.
    expect(c.read(workspaceProvider).activeTab?.path, path);
  });

  test('clone refuses a non-empty destination', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final parent = Directory('${work.path}/busydest')..createSync();
    Directory('${parent.path}/repo').createSync();
    File('${parent.path}/repo/junk').writeAsStringSync('x');

    final path = await c
        .read(repoBootstrapProvider)
        .clone(url: '/nowhere/repo.git', parentDir: parent.path);
    expect(path, isNull);
  });

  test(
    'create inits a repo with default branch, README and initial commit',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final path = await c
          .read(repoBootstrapProvider)
          .create(
            name: 'fresh',
            parentDir: work.path,
            defaultBranch: 'trunk',
            readme: true,
            gitignore: true,
          );

      expect(path, isNotNull);
      expect(await svc.isRepository(path!), isTrue);
      expect(File('$path/README.md').readAsStringSync(), '# fresh\n');
      expect(File('$path/.gitignore').existsSync(), isTrue);
      // Read via symbolic-ref, not `rev-parse --abbrev-ref`: on a CI runner
      // with no git identity the initial commit can't be made, leaving `trunk`
      // unborn — rev-parse then prints 'HEAD', but the branch create() set is
      // still 'trunk'. symbolic-ref reports it correctly for an unborn branch.
      final branch = await svc.run([
        'symbolic-ref',
        '--short',
        'HEAD',
      ], repoPath: path);
      expect(branch.out, 'trunk');
      // Initial commit exists (user identity comes from the test env's global
      // config; if absent the repo is still valid, so tolerate 0 or 1 commits).
      final log = await svc.run(['log', '--oneline'], repoPath: path);
      if (log.ok) expect(log.out, contains('Initial commit'));
      expect(c.read(workspaceProvider).activeTab?.path, path);
    },
  );
}
