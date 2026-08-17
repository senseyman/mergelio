import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/domain/path_key.dart';

/// Integration tests: drive real `git worktree` through GitReader/GitWriter.
void main() {
  const svc = SystemGitService();
  late Directory repo;
  final extra = <Directory>[];

  Future<void> g(Directory d, List<String> a) async {
    final r = await svc.run(a, repoPath: d.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_wt_');
    await g(repo, ['init', '-q', '-b', 'main']);
    await g(repo, ['config', 'user.email', 't@e.com']);
    await g(repo, ['config', 'user.name', 'T']);
    await g(repo, ['config', 'commit.gpgsign', 'false']);
    await File('${repo.path}/a.txt').writeAsString('a\n');
    await g(repo, ['add', '.']);
    await g(repo, ['commit', '-q', '-m', 'base']);
  });

  tearDown(() async {
    for (final d in [repo, ...extra]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
    extra.clear();
  });

  GitReader reader() => GitReader(svc, repo.path);
  GitWriter writer() => GitWriter(svc, repo.path);

  String sibling(String suffix) {
    final p = '${repo.path}$suffix';
    extra.add(Directory(p));
    return p;
  }

  test('a fresh repo lists only its main worktree', () async {
    final list = await reader().worktrees();
    expect(list.length, 1);
    expect(list.single.kind, WorktreeKind.main);
    expect(list.single.branch, 'main');
    expect(samePath(list.single.path, repo.path), isTrue);
  });

  test('add creates a linked worktree on a new branch', () async {
    final at = sibling('-feat');
    await writer().addWorktree(at, newBranch: 'feat/x', startPoint: 'main');
    final list = await reader().worktrees();
    expect(list.length, 2);
    final linked = list[1];
    expect(linked.kind, WorktreeKind.linked);
    expect(linked.branch, 'feat/x');
    expect(samePath(linked.path, at), isTrue);
    expect(File('$at/a.txt').existsSync(), isTrue);
    final holder = worktreeHolding(list, 'feat/x');
    expect(holder, isNotNull);
    expect(
      samePath(holder!.path, at),
      isTrue,
      reason: 'the holder is the worktree just created, not merely non-null',
    );
  });

  test('add --detach yields a detached worktree with no branch', () async {
    final at = sibling('-det');
    await writer().addWorktree(at, detach: true, startPoint: 'HEAD');
    final linked = (await reader().worktrees())[1];
    expect(linked.detached, isTrue);
    expect(linked.branch, isNull);
    expect(linked.shortHead, hasLength(7));
  });

  test('lock then unlock round-trips through the porcelain flags', () async {
    final at = sibling('-lock');
    await writer().addWorktree(at, newBranch: 'lk', startPoint: 'main');
    await writer().lockWorktree(at, reason: 'on usb');
    var linked = (await reader().worktrees())[1];
    expect(linked.locked, isTrue);
    // The reason field needs git >= 2.36; the flag itself is older.
    expect(linked.lockReason, anyOf(isNull, 'on usb'));
    await writer().unlockWorktree(at);
    linked = (await reader().worktrees())[1];
    expect(linked.locked, isFalse);
  });

  test('move relocates a worktree', () async {
    final from = sibling('-from');
    final to = sibling('-to');
    await writer().addWorktree(from, newBranch: 'mv', startPoint: 'main');
    await writer().moveWorktree(from, to);
    final linked = (await reader().worktrees())[1];
    expect(samePath(linked.path, to), isTrue);
    expect(Directory(from).existsSync(), isFalse);
  });

  test('remove deletes a clean worktree', () async {
    final at = sibling('-rm');
    await writer().addWorktree(at, newBranch: 'rm', startPoint: 'main');
    await writer().removeWorktree(at);
    expect((await reader().worktrees()).length, 1);
    expect(Directory(at).existsSync(), isFalse);
  });

  test('remove refuses a dirty worktree until forced', () async {
    final at = sibling('-dirty');
    await writer().addWorktree(at, newBranch: 'dirty', startPoint: 'main');
    await File('$at/a.txt').writeAsString('changed\n');
    await expectLater(
      writer().removeWorktree(at),
      throwsA(isA<GitException>()),
    );
    await writer().removeWorktree(at, force: true);
    expect((await reader().worktrees()).length, 1);
  });

  test('remove refuses the main worktree', () async {
    await expectLater(
      writer().removeWorktree(repo.path),
      throwsA(isA<GitException>()),
    );
  });

  test('checking out a held branch fails, and --ignore-other-worktrees '
      'overrides it — the collision this feature exists to prevent', () async {
    final at = sibling('-held');
    await writer().addWorktree(at, newBranch: 'held', startPoint: 'main');

    final r = await svc.run(['checkout', 'held'], repoPath: repo.path);
    // The exit code is the contract; git's English is not, and it has been
    // reworded before. The message check is a nicety, so it only has to hold
    // when git said something at all.
    expect(r.ok, isFalse);
    expect(r.err, anyOf(isEmpty, contains('already used by worktree')));

    // Proves the escape hatch the collision dialog offers actually works
    // against real git, rather than only that the flag reaches the argv.
    await writer().checkout('held', ignoreOtherWorktrees: true);
    final head = await svc.run([
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ], repoPath: repo.path);
    expect(head.out.trim(), 'held');
  });

  test(
    'prune --dry-run reports a vanished worktree without removing it',
    () async {
      final at = sibling('-gone');
      await writer().addWorktree(at, newBranch: 'gone', startPoint: 'main');
      await Directory(at).delete(recursive: true);
      final report = await writer().pruneWorktrees(dryRun: true);
      expect(report, isNotEmpty);
      expect((await reader().worktrees()).length, 2, reason: 'dry run only');
      await writer().pruneWorktrees();
      expect((await reader().worktrees()).length, 1);
    },
  );
}
