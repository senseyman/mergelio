import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/path_key.dart';
import 'package:mergelio/state/worktrees.dart';

/// Integration tests: resolveGitDir, isLinkedWorktreeProvider and
/// worktreeParentProvider against a real repo and a real linked worktree
/// created through GitWriter.addWorktree.
void main() {
  const svc = SystemGitService();
  late Directory repo;
  late Directory linked;

  Future<void> g(Directory d, List<String> a) async {
    final r = await svc.run(a, repoPath: d.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_wtwatch_');
    await g(repo, ['init', '-q', '-b', 'main']);
    await g(repo, ['config', 'user.email', 't@e.com']);
    await g(repo, ['config', 'user.name', 'T']);
    await g(repo, ['config', 'commit.gpgsign', 'false']);
    await File('${repo.path}/a.txt').writeAsString('a\n');
    await g(repo, ['add', '.']);
    await g(repo, ['commit', '-q', '-m', 'base']);

    linked = Directory('${repo.path}-linked');
    await GitWriter(
      svc,
      repo.path,
    ).addWorktree(linked.path, newBranch: 'wt', startPoint: 'main');
  });

  tearDown(() async {
    for (final d in [linked, repo]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  test('a linked worktree keeps a .git file, not a directory', () {
    expect(File('${linked.path}/.git').existsSync(), isTrue);
    expect(Directory('${linked.path}/.git').existsSync(), isFalse);
    expect(Directory('${repo.path}/.git').existsSync(), isTrue);
  });

  test('resolveGitDir points into the main repo for a linked worktree', () {
    final dir = resolveGitDir(linked.path);
    expect(dir, isNotNull);
    expect(dir, contains('worktrees'));
    expect(Directory(dir!).existsSync(), isTrue);
    expect(File('$dir/HEAD').existsSync(), isTrue);
  });

  test('resolveGitDir returns the plain .git dir for a normal checkout', () {
    expect(resolveGitDir(repo.path), '${repo.path}/.git');
  });

  test('resolveGitDir returns null when there is no git state', () async {
    final plain = await Directory.systemTemp.createTemp('mergelio_plain_');
    addTearDown(() => plain.delete(recursive: true));
    expect(resolveGitDir(plain.path), isNull);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test(
    'isLinkedWorktreeProvider tells a linked worktree from a clone',
    () async {
      final c = container();
      expect(
        await c.read(isLinkedWorktreeProvider(linked.path).future),
        isTrue,
      );
      expect(await c.read(isLinkedWorktreeProvider(repo.path).future), isFalse);
    },
  );

  test(
    'isLinkedWorktreeProvider is false for a directory with no git state',
    () async {
      final plain = await Directory.systemTemp.createTemp('mergelio_plain_');
      addTearDown(() => plain.delete(recursive: true));
      expect(
        await container().read(isLinkedWorktreeProvider(plain.path).future),
        isFalse,
      );
    },
  );

  test('isLinkedWorktreeProvider is false for a submodule checkout', () async {
    // A submodule also keeps a `.git` file instead of a directory, so the
    // presence of that file alone cannot answer the question — its pointer
    // has to name a worktree admin directory. Otherwise a submodule opened as
    // a tab wears the worktree glyph and claims a parent it does not have.
    final sub = await Directory.systemTemp.createTemp('mergelio_sub_');
    addTearDown(() => sub.delete(recursive: true));
    await File(
      '${sub.path}/.git',
    ).writeAsString('gitdir: ${repo.path}/.git/modules/vendor\n');
    expect(
      await container().read(isLinkedWorktreeProvider(sub.path).future),
      isFalse,
    );
  });

  test(
    'worktreeParentProvider names the repository a linked worktree belongs to',
    () async {
      final parent = await container().read(
        worktreeParentProvider(linked.path).future,
      );
      expect(parent, isNotNull);
      expect(samePath(parent!, repo.path), isTrue);
    },
  );

  test('worktreeParentProvider is null for the main checkout', () async {
    expect(
      await container().read(worktreeParentProvider(repo.path).future),
      isNull,
    );
  });

  test('worktreeParentProvider refuses a gitdir that is not a worktree admin '
      'directory', () async {
    // A submodule's `.git` file points at `.git/modules/<name>`, and a linked
    // worktree may itself be named `.git`. Cutting at the last `.git` segment
    // without checking that `worktrees` follows it named the wrong directory
    // as the parent instead of admitting there is none.
    Future<String?> parentFor(String pointer) async {
      final dir = await Directory.systemTemp.createTemp('mergelio_ptr_');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/.git').writeAsString('gitdir: $pointer\n');
      return container().read(worktreeParentProvider(dir.path).future);
    }

    expect(await parentFor('/home/u/repo/.git/modules/vendor'), isNull);
    expect(await parentFor('/home/u/repo/.git/worktrees/.git'), isNull);
    expect(await parentFor('nonsense'), isNull);
    expect(
      await parentFor('/home/u/repo/.git/worktrees/login'),
      '/home/u/repo',
      reason: 'the real shape still resolves',
    );
  });
}
