// Which commits changed a string in their diff. Read from git's pickaxe, since
// a loaded commit carries neither its diff nor its file list.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/search.dart';
import 'package:mergelio/state/content_search.dart';

class _FakeGit implements GitService {
  final GitResult result;
  final Object? throws;
  final calls = <List<String>>[];
  _FakeGit(this.result, {this.throws});

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add(a);
    if (throws != null) throw throws!;
    return result;
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  ProviderContainer container(_FakeGit git) {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the shas git reports for the string are returned', () async {
    final git = _FakeGit(const GitResult(0, 'aaa\nbbb\nccc\n', ''));
    final c = container(git);

    final shas = await c.read(
      contentSearchProvider(const ContentKey('/r', 'parseUrl')).future,
    );

    expect(shas, {'aaa', 'bbb', 'ccc'});
  });

  test('the default mode counts occurrences of the literal string', () async {
    final git = _FakeGit(const GitResult(0, '', ''));
    final c = container(git);

    await c.read(
      contentSearchProvider(const ContentKey('/r', 'parseUrl')).future,
    );

    final args = git.calls.single;
    expect(args.first, 'log');
    expect(args, contains('-SparseUrl'));
    expect(args, isNot(contains('--pickaxe-regex')));
  });

  test(
    'every branch is searched, since the graph shows every branch',
    () async {
      final git = _FakeGit(const GitResult(0, '', ''));
      final c = container(git);

      await c.read(
        contentSearchProvider(const ContentKey('/r', 'parseUrl')).future,
      );

      expect(git.calls.single, contains('--all'));
    },
  );

  test('regex mode matches added and removed lines instead', () async {
    final git = _FakeGit(const GitResult(0, '', ''));
    final c = container(git);

    await c.read(
      contentSearchProvider(
        const ContentKey('/r', 'parse.*Url', ContentSearchMode.diffText),
      ).future,
    );

    expect(git.calls.single, contains('-Gparse.*Url'));
  });

  test('a string that looks like an option is still a search string', () async {
    final git = _FakeGit(const GitResult(0, '', ''));
    final c = container(git);

    await c.read(
      contentSearchProvider(const ContentKey('/r', '--force')).future,
    );

    expect(git.calls.single, contains('-S--force'));
  });

  test('an empty string never reaches git', () async {
    final git = _FakeGit(const GitResult(0, 'aaa\n', ''));
    final c = container(git);

    expect(
      await c.read(contentSearchProvider(const ContentKey('/r', '')).future),
      isEmpty,
    );
    expect(git.calls, isEmpty);
  });

  test('a failed read reports nothing rather than throwing', () async {
    final git = _FakeGit(const GitResult(128, '', 'fatal: bad regex'));
    final c = container(git);

    expect(
      await c.read(contentSearchProvider(const ContentKey('/r', 'x')).future),
      isEmpty,
    );
  });

  test('a hung or killed git reports nothing rather than throwing', () async {
    final git = _FakeGit(
      const GitResult(0, '', ''),
      throws: GitException('timed out'),
    );
    final c = container(git);

    expect(
      await c.read(contentSearchProvider(const ContentKey('/r', 'x')).future),
      isEmpty,
    );
  });

  test('keys differing only in mode are different searches', () {
    const a = ContentKey('/r', 'x');
    const b = ContentKey('/r', 'x', ContentSearchMode.diffText);

    expect(a, const ContentKey('/r', 'x'));
    expect(a == b, isFalse);
    expect(a.hashCode == b.hashCode, isFalse);
  });

  test(
    'a real repo reports only the commits that changed the string',
    () async {
      const svc = SystemGitService();
      final repo = await Directory.systemTemp.createTemp('mergelio_pickaxe_');
      addTearDown(() async {
        if (await repo.exists()) await repo.delete(recursive: true);
      });
      Future<void> g(List<String> args) async {
        final r = await svc.run(args, repoPath: repo.path);
        if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
      }

      await g(['init', '-q', '-b', 'main']);
      await g(['config', 'user.email', 't@e.com']);
      await g(['config', 'user.name', 'T']);
      await g(['config', 'commit.gpgsign', 'false']);
      await File('${repo.path}/a.txt').writeAsString('hello\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'first']);
      await File('${repo.path}/a.txt').writeAsString('hello\nneedle\n');
      await g(['commit', '-q', '-am', 'add needle']);
      await File('${repo.path}/a.txt').writeAsString('hello\nother\n');
      await g(['commit', '-q', '-am', 'drop needle']);
      await File('${repo.path}/b.txt').writeAsString('unrelated\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'unrelated']);

      final c = ProviderContainer();
      addTearDown(c.dispose);

      final shas = await c.read(
        contentSearchProvider(ContentKey(repo.path, 'needle')).future,
      );

      // The commit that added the line and the one that removed it, not the two
      // that never mention it.
      expect(shas, hasLength(2));
    },
  );

  test('a hit on a branch that is not checked out is still found', () async {
    const svc = SystemGitService();
    final repo = await Directory.systemTemp.createTemp('mergelio_pickaxe_br_');
    addTearDown(() async {
      if (await repo.exists()) await repo.delete(recursive: true);
    });
    Future<void> g(List<String> args) async {
      final r = await svc.run(args, repoPath: repo.path);
      if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }

    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${repo.path}/a.txt').writeAsString('hello\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'first']);
    await g(['checkout', '-q', '-b', 'side']);
    await File('${repo.path}/a.txt').writeAsString('hello\nneedle\n');
    await g(['commit', '-q', '-am', 'add needle on side']);
    await g(['checkout', '-q', 'main']);

    final c = ProviderContainer();
    addTearDown(c.dispose);

    // The graph draws every branch, so a search that only walked HEAD would
    // dim a commit that is sitting right there on screen.
    final shas = await c.read(
      contentSearchProvider(ContentKey(repo.path, 'needle')).future,
    );

    expect(shas, hasLength(1));
  });
}
