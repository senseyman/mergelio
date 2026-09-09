import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_data.dart';

/// Counts the bulk history walks a load performs, so a refresh that reuses the
/// cached commit list can be told apart from one that walks again.
class _CountingGit implements GitService {
  final GitService _inner;
  var logWalks = 0;

  _CountingGit(this._inner);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) {
    if (args.first == 'log' && args.contains('--all')) logWalks++;
    return _inner.run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
    );
  }

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);

  @override
  Future<String> version() => _inner.version();
}

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> commit(String name) async {
    await File('${dir.path}/$name').writeAsString('$name\n');
    await g(['add', name]);
    await g(['commit', '-q', '-m', name]);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_paging_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    for (final n in ['a', 'b', 'c', 'd', 'e']) {
      await commit(n);
    }
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('paging', () {
    test('loads only the first page and reports more are available', () async {
      final container = ProviderContainer(
        overrides: [commitLimitProvider(dir.path).overrideWith((_) => 2)],
      );
      addTearDown(container.dispose);

      final data = await container.read(repoDataProvider(dir.path).future);

      expect(data.commits, hasLength(2));
      expect(data.hasMoreCommits, isTrue);
    });

    test('a limit past the end of history reports no more commits', () async {
      final container = ProviderContainer(
        overrides: [commitLimitProvider(dir.path).overrideWith((_) => 500)],
      );
      addTearDown(container.dispose);

      final data = await container.read(repoDataProvider(dir.path).future);

      expect(data.commits, hasLength(5));
      expect(data.hasMoreCommits, isFalse);
    });

    test('raising the limit extends the loaded history', () async {
      final container = ProviderContainer(
        overrides: [commitLimitProvider(dir.path).overrideWith((_) => 2)],
      );
      addTearDown(container.dispose);
      await container.read(repoDataProvider(dir.path).future);

      container.read(commitLimitProvider(dir.path).notifier).state = 4;
      final data = await container.read(repoDataProvider(dir.path).future);

      expect(data.commits, hasLength(4));
      expect(data.hasMoreCommits, isTrue);
    });

    test('the default limit is one page', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(commitLimitProvider(dir.path)), commitPageSize);
    });
  });

  group('commit cache', () {
    test('a refresh with no ref movement reuses the walked commits', () async {
      final git = _CountingGit(svc);
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(container.dispose);

      final first = await container.read(repoDataProvider(dir.path).future);
      final walksAfterLoad = git.logWalks;

      // A working-tree-only change: the watcher fires, but no ref moved.
      await File('${dir.path}/a').writeAsString('edited\n');
      container.invalidate(repoDataProvider(dir.path));
      final second = await container.read(repoDataProvider(dir.path).future);

      expect(git.logWalks, walksAfterLoad, reason: 'history walked again');
      expect(second.commits.map((c) => c.sha), first.commits.map((c) => c.sha));
      // The reused list keeps its layout; it is not raw reader output.
      expect(second.working, isNotEmpty);
    });

    test('a new commit invalidates the cached commits', () async {
      final git = _CountingGit(svc);
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(container.dispose);

      final first = await container.read(repoDataProvider(dir.path).future);
      final walksAfterLoad = git.logWalks;

      await commit('f');
      container.invalidate(repoDataProvider(dir.path));
      final second = await container.read(repoDataProvider(dir.path).future);

      expect(git.logWalks, greaterThan(walksAfterLoad));
      expect(second.commits.length, first.commits.length + 1);
    });

    test('holding every repo ever opened is bounded', () async {
      // The cached list is the whole loaded history, so an unbounded map would
      // pin the commits of every repository the session ever touched.
      final others = <Directory>[];
      addTearDown(() async {
        for (final d in others) {
          if (await d.exists()) await d.delete(recursive: true);
        }
      });
      final git = _CountingGit(svc);
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(container.dispose);

      await container.read(repoDataProvider(dir.path).future);

      for (var i = 0; i <= commitCacheLimit; i++) {
        final other = await Directory.systemTemp.createTemp('mergelio_other_');
        others.add(other);
        final r = await svc.run(['init', '-q'], repoPath: other.path);
        if (!r.ok) throw StateError('init failed: ${r.err}');
        await container.read(repoDataProvider(other.path).future);
      }

      final walksBefore = git.logWalks;
      container.invalidate(repoDataProvider(dir.path));
      await container.read(repoDataProvider(dir.path).future);

      expect(git.logWalks, greaterThan(walksBefore));
    });

    test(
      'raising the limit re-walks rather than reusing a short page',
      () async {
        final git = _CountingGit(svc);
        final container = ProviderContainer(
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            commitLimitProvider(dir.path).overrideWith((_) => 2),
          ],
        );
        addTearDown(container.dispose);

        await container.read(repoDataProvider(dir.path).future);
        final walksAfterLoad = git.logWalks;

        container.read(commitLimitProvider(dir.path).notifier).state = 4;
        final data = await container.read(repoDataProvider(dir.path).future);

        expect(git.logWalks, greaterThan(walksAfterLoad));
        expect(data.commits, hasLength(4));
      },
    );
  });
}
