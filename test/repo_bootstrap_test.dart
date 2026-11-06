import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/clone_options.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/data/app_database.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/state/recents.dart';
import 'package:mergelio/state/repo_bootstrap.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:path/path.dart' as p;

/// Records every git call and runs none.
class _RecordingGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Keeps recents in memory; the real repository writes to the app database.
class _MemoryRecents implements RecentsRepository {
  @override
  AppDatabase get db => throw UnimplementedError();
  @override
  Future<List<RecentRepo>> load() async => const [];
  @override
  Future<void> save(List<RecentRepo> items) async {}
}

/// A container whose recents list works, so opening a repo records it.
ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [
      recentsProvider.overrideWith(
        (ref) => RecentsController(_MemoryRecents(), const []),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

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

  group('staysInsideParent', () {
    test('accepts plain child names on both platforms', () {
      expect(
        RepoBootstrap.staysInsideParent('/repos', 'repo', context: p.posix),
        isTrue,
      );
      expect(
        RepoBootstrap.staysInsideParent(
          r'C:\repos',
          'repo',
          context: p.windows,
        ),
        isTrue,
      );
    });

    test('rejects absolute names, which make join discard the parent', () {
      expect(
        RepoBootstrap.staysInsideParent('/repos', '/evil', context: p.posix),
        isFalse,
      );
      expect(
        RepoBootstrap.staysInsideParent(
          r'C:\repos',
          r'C:\evil',
          context: p.windows,
        ),
        isFalse,
      );
      expect(
        RepoBootstrap.staysInsideParent(
          r'C:\repos',
          r'D:\evil',
          context: p.windows,
        ),
        isFalse,
      );
    });

    test('rejects names that climb out via dot-dot segments', () {
      expect(
        RepoBootstrap.staysInsideParent('/repos', '../evil', context: p.posix),
        isFalse,
      );
      expect(
        RepoBootstrap.staysInsideParent(
          '/repos',
          'a/../../evil',
          context: p.posix,
        ),
        isFalse,
      );
    });
  });

  test('clone refuses a folder name that escapes the parent', () async {
    final c = _container();
    final parent = Directory('${work.path}/parent')..createSync();

    final path = await c
        .read(repoBootstrapProvider)
        .clone(
          url: '/nowhere/repo.git',
          parentDir: parent.path,
          folderName: '../evil',
        );

    expect(path, isNull);
    expect(Directory('${work.path}/evil').existsSync(), isFalse);
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

    final c = _container();
    final parent = Directory('${work.path}/clones')..createSync();

    final path = await c
        .read(repoBootstrapProvider)
        .clone(url: origin.path, parentDir: parent.path);

    expect(path, isNotNull);
    expect(File('$path/a.txt').existsSync(), isTrue);
    expect(await svc.isRepository(path!), isTrue);
    // Opened as the active tab.
    expect(c.read(workspaceProvider).activeTab?.path, path);
    expect(c.read(recentsProvider).first.path, path);
  });

  group('clone options', () {
    late Directory origin;

    // Three commits on main, one more on dev, and a submodule on main.
    setUp(() async {
      Future<void> g(String dir, List<String> args) async {
        final r = await svc.run([
          '-c',
          'protocol.file.allow=always',
          ...args,
        ], repoPath: dir);
        if (!r.ok) throw StateError('git ${args.join(' ')}: ${r.err}');
      }

      Future<void> init(Directory d) async {
        d.createSync();
        await g(d.path, ['init', '-q', '-b', 'main']);
        await g(d.path, ['config', 'user.email', 't@e.com']);
        await g(d.path, ['config', 'user.name', 'T']);
        await g(d.path, ['config', 'commit.gpgsign', 'false']);
      }

      final sub = Directory('${work.path}/sub');
      await init(sub);
      await File('${sub.path}/s.txt').writeAsString('S\n');
      await g(sub.path, ['add', '.']);
      await g(sub.path, ['commit', '-q', '-m', 'S']);

      origin = Directory('${work.path}/origin');
      await init(origin);
      for (final n in ['1', '2', '3']) {
        await File('${origin.path}/f$n').writeAsString('$n\n');
        await g(origin.path, ['add', '.']);
        await g(origin.path, ['commit', '-q', '-m', 'c$n']);
      }
      await g(origin.path, ['submodule', 'add', '-q', sub.path, 'sub']);
      await g(origin.path, ['commit', '-q', '-m', 'sub']);
      await g(origin.path, ['checkout', '-q', '-b', 'dev']);
      await File('${origin.path}/d').writeAsString('d\n');
      await g(origin.path, ['add', '.']);
      await g(origin.path, ['commit', '-q', '-m', 'd']);
      await g(origin.path, ['checkout', '-q', 'main']);
    });

    Future<String?> cloneWith(CloneOptions o, {String? url}) async {
      final c = _container();
      final parent = Directory('${work.path}/clones')..createSync();
      return c
          .read(repoBootstrapProvider)
          .clone(
            url: url ?? origin.path,
            parentDir: parent.path,
            folderName: 'c',
            options: o,
          );
    }

    Future<String> out(String repo, List<String> args) async =>
        (await svc.run(args, repoPath: repo)).out;

    test('shallow from a local path really is shallow', () async {
      final path = await cloneWith(
        const CloneOptions(depth: 1, submodules: false),
      );
      expect(path, isNotNull);
      expect(
        await out(path!, ['rev-parse', '--is-shallow-repository']),
        'true',
      );
      expect(await out(path, ['rev-list', '--count', 'HEAD']), '1');
      // Not narrowed to one branch unless asked.
      expect(await out(path, ['branch', '-r']), contains('origin/dev'));
    });

    test('single branch fetches only that branch and checks it out', () async {
      final path = await cloneWith(
        // git refuses file:// submodules by default; not what is tested.
        const CloneOptions(
          branch: 'dev',
          singleBranch: true,
          submodules: false,
        ),
        url: Uri.file(origin.path).toString(),
      );
      expect(path, isNotNull);
      expect(await out(path!, ['branch', '--show-current']), 'dev');
      final remotes = await out(path, ['branch', '-r']);
      expect(remotes, contains('origin/dev'));
      expect(remotes, isNot(contains('origin/main')));
    });

    test('blobless sets up a partial clone', () async {
      final path = await cloneWith(
        const CloneOptions(blobless: true, submodules: false),
      );
      expect(path, isNotNull);
      expect(
        await out(path!, ['config', 'remote.origin.partialclonefilter']),
        'blob:none',
      );
    });

    test('submodules off leaves the submodule unpopulated', () async {
      final path = await cloneWith(const CloneOptions(submodules: false));
      expect(path, isNotNull);
      expect(File('$path/sub/s.txt').existsSync(), isFalse);
    });

    test('an unknown branch fails and leaves nothing behind', () async {
      final path = await cloneWith(
        const CloneOptions(branch: 'nope', singleBranch: true),
      );
      expect(path, isNull);
      expect(Directory('${work.path}/clones/c').existsSync(), isFalse);
    });

    test('invalid options are refused before git runs', () async {
      for (final o in const [
        CloneOptions(depth: 0),
        CloneOptions(branch: 'a..b', singleBranch: true),
      ]) {
        final git = _RecordingGit();
        final c = ProviderContainer(
          overrides: [gitServiceProvider.overrideWithValue(git)],
        );
        addTearDown(c.dispose);
        final parent = Directory('${work.path}/clones')..createSync();

        final path = await c
            .read(repoBootstrapProvider)
            .clone(url: origin.path, parentDir: parent.path, options: o);

        expect(path, isNull);
        expect(git.calls, isEmpty);
      }
    });
  });

  test('clone refuses a non-empty destination', () async {
    final c = _container();
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
      final c = _container();

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
