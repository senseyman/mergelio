import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';

/// Squash-link inference runs `git merge-base` once per branch it examines, so
/// counting that command says exactly how many branches a reload re-examined.
class _CountingGit implements GitService {
  final GitService _inner;
  var mergeBases = 0;

  _CountingGit(this._inner);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) {
    if (args.isNotEmpty && args.first == 'merge-base') mergeBases++;
    return _inner.run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
    );
  }

  @override
  Future<String> version() => _inner.version();

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);
}

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> commit(String file, String msg) async {
    await File('${dir.path}/$file').writeAsString('$msg\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', msg]);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_squash_inc_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await commit('a.txt', 'A');

    // Two side branches, each on its own commit, so every branch tip differs.
    await g(['checkout', '-q', '-b', 'one']);
    await commit('b.txt', 'B');
    await g(['checkout', '-q', 'main']);
    await g(['checkout', '-q', '-b', 'two']);
    await commit('c.txt', 'C');
    await g(['checkout', '-q', 'main']);
    await commit('d.txt', 'D');
  });

  tearDown(() async {
    squashLinkCache.forget(dir.path);
    await dir.delete(recursive: true);
  });

  test('creating a branch on a fresh commit infers only that branch', () async {
    final git = _CountingGit(svc);
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    c.listen(repoDataProvider(dir.path), (_, _) {}, fireImmediately: true);

    await c.read(repoDataProvider(dir.path).future);
    expect(
      git.mergeBases,
      2,
      reason:
          'the first load examines both branches other than the current one',
    );

    // `main~1` is the root commit, which no branch points at, so the new branch
    // is a question nothing already answered.
    git.mergeBases = 0;
    await c
        .read(repoActionsProvider(dir.path))
        .createBranch('three', at: 'main~1');
    await Future<void>.delayed(actionSettle * 6);
    final data = await c.read(repoDataProvider(dir.path).future);

    expect(
      git.mergeBases,
      1,
      reason: 'only the new branch is unknown; the rest have not moved',
    );
    expect(data.branches.map((b) => b.name), containsAll(['one', 'three']));
  });

  test('a branch created on an existing tip infers nothing', () async {
    // What creating a branch and checking it out leaves behind. The inference
    // resolves the current branch to a commit and never looks at its name, so
    // landing on a commit already accounted for cannot change any answer.
    final git = _CountingGit(svc);
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    c.listen(repoDataProvider(dir.path), (_, _) {}, fireImmediately: true);

    await c.read(repoDataProvider(dir.path).future);
    git.mergeBases = 0;

    final actions = c.read(repoActionsProvider(dir.path));
    await actions.createBranch('side');
    await actions.checkout('side');
    await Future<void>.delayed(actionSettle * 6);
    final data = await c.read(repoDataProvider(dir.path).future);

    expect(git.mergeBases, 0);
    expect(data.branches.firstWhere((b) => b.current).name, 'side');
  });

  test('a reload that changed nothing infers nothing', () async {
    final git = _CountingGit(svc);
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    c.listen(repoDataProvider(dir.path), (_, _) {}, fireImmediately: true);

    await c.read(repoDataProvider(dir.path).future);
    git.mergeBases = 0;

    c.invalidate(repoDataProvider(dir.path));
    await c.read(repoDataProvider(dir.path).future);

    expect(git.mergeBases, 0);
  });
}
