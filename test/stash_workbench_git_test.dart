import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/stash.dart';

/// Integration tests: real repositories built with the system `git`, read and
/// written through [GitReader] / [GitWriter].
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out;

  Future<void> write(String name, String content) async {
    final f = File('${dir.path}/$name');
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  Future<String> read(String name) => File('${dir.path}/$name').readAsString();
  bool exists(String name) => File('${dir.path}/$name').existsSync();

  GitReader reader() => GitReader(svc, dir.path);
  GitWriter writer() => GitWriter(svc, dir.path);

  Future<String> status() async =>
      (await svc.run(['status', '--porcelain'], repoPath: dir.path)).stdout;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_stash_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await write('a.txt', 'one\ntwo\nthree\n');
    await write('b.txt', 'b\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('stashContents', () {
    test('lists tracked changes against the base commit', () async {
      await write('a.txt', 'one\nTWO\nthree\n');
      await g(['rm', '-q', 'b.txt']);
      await g(['stash', 'push', '-q']);
      final sha = await out(['rev-parse', 'stash@{0}']);

      final c = await reader().stashContents(sha);

      expect(c.baseSha, await out(['rev-parse', 'HEAD']));
      expect(c.untrackedSha, isNull);
      expect(c.untracked, isEmpty);
      expect(c.files, [
        const CommitFileChange(path: 'a.txt', change: GitChange.modified),
        const CommitFileChange(path: 'b.txt', change: GitChange.deleted),
      ]);
    });

    test('lists untracked files of an -u stash separately', () async {
      await write('a.txt', 'changed\n');
      await write('new/c.txt', 'c\n');
      await g(['stash', 'push', '-q', '-u']);
      final sha = await out(['rev-parse', 'stash@{0}']);

      final c = await reader().stashContents(sha);

      expect(c.untrackedSha, await out(['rev-parse', 'stash@{0}^3']));
      expect(c.untracked, ['new/c.txt']);
      expect(c.files.map((f) => f.path), ['a.txt']);
    });
  });

  group('stashFilePatch', () {
    test('a tracked file patch applies back onto the clean tree', () async {
      await write('a.txt', 'one\nTWO\nthree\n');
      await write('b.txt', 'B\n');
      await g(['stash', 'push', '-q']);
      final sha = await out(['rev-parse', 'stash@{0}']);
      final c = await reader().stashContents(sha);

      final patch = await reader().stashFilePatch(sha, c, path: 'a.txt');
      await writer().applyToWorktree(patch);

      expect(await read('a.txt'), 'one\nTWO\nthree\n');
      expect(await read('b.txt'), 'b\n', reason: 'only the one file');
      expect(await status(), ' M a.txt\n', reason: 'worktree only');
    });

    test('an untracked file patch recreates the file', () async {
      await write('n.txt', 'new\n');
      await g(['stash', 'push', '-q', '-u']);
      final sha = await out(['rev-parse', 'stash@{0}']);
      final c = await reader().stashContents(sha);

      final patch = await reader().stashFilePatch(
        sha,
        c,
        path: 'n.txt',
        untracked: true,
      );
      await writer().applyToWorktree(patch);

      expect(await read('n.txt'), 'new\n');
    });

    test('a deletion patch removes the file', () async {
      await g(['rm', '-q', 'b.txt']);
      await g(['stash', 'push', '-q']);
      final sha = await out(['rev-parse', 'stash@{0}']);
      final c = await reader().stashContents(sha);

      final patch = await reader().stashFilePatch(sha, c, path: 'b.txt');
      await writer().applyToWorktree(patch);

      expect(exists('b.txt'), isFalse);
    });

    test('a binary file patch applies', () async {
      await File('${dir.path}/bin.dat').writeAsBytes([0, 1, 2, 0, 255]);
      await g(['add', 'bin.dat']);
      await g(['commit', '-q', '-m', 'bin']);
      await File('${dir.path}/bin.dat').writeAsBytes([0, 9, 9, 0, 255, 7]);
      await g(['stash', 'push', '-q']);
      final sha = await out(['rev-parse', 'stash@{0}']);
      final c = await reader().stashContents(sha);

      final patch = await reader().stashFilePatch(sha, c, path: 'bin.dat');
      await writer().applyToWorktree(patch);

      expect(await File('${dir.path}/bin.dat').readAsBytes(), [
        0,
        9,
        9,
        0,
        255,
        7,
      ]);
    });
  });

  group('stashPush options', () {
    test('a pathspec stashes only the named file', () async {
      await write('a.txt', 'A\n');
      await write('b.txt', 'B\n');

      await writer().stashPush(const StashPushOptions(paths: ['b.txt']));

      expect(await read('a.txt'), 'A\n');
      expect(await read('b.txt'), 'b\n');
      expect(await out(['stash', 'list']), isNotEmpty);
    });

    test('a pathspec with glob characters is taken literally', () async {
      await write('*.txt', 'star\n');
      await g(['add', '*.txt']);
      await g(['commit', '-q', '-m', 'star']);
      await write('*.txt', 'STAR\n');
      await write('a.txt', 'A\n');

      await writer().stashPush(const StashPushOptions(paths: ['*.txt']));

      expect(await read('*.txt'), 'star\n');
      expect(await read('a.txt'), 'A\n', reason: 'not matched by a glob');
    });

    test('keep-index leaves the staged change in place', () async {
      await write('a.txt', 'A\n');
      await g(['add', 'a.txt']);
      await write('b.txt', 'B\n');

      await writer().stashPush(const StashPushOptions(keepIndex: true));

      expect(await status(), 'M  a.txt\n');
    });

    test('include-untracked takes new files too', () async {
      await write('n.txt', 'new\n');

      await writer().stashPush(
        const StashPushOptions(includeUntracked: true, message: 'with new'),
      );

      expect(exists('n.txt'), isFalse);
      expect((await reader().stashes()).single.message, contains('with new'));
    });
  });

  group('stashRename', () {
    test('keeps the stash commit and gives it the new message', () async {
      await write('a.txt', 'first\n');
      await g(['stash', 'push', '-q', '-m', 'first']);
      await write('a.txt', 'second\n');
      await g(['stash', 'push', '-q', '-m', 'second']);
      final sha = await out(['rev-parse', 'stash@{1}']);

      await writer().stashRename('stash@{1}', 'renamed');

      final list = await reader().stashes();
      expect(list, hasLength(2));
      final renamed = list.singleWhere((s) => s.sha == sha);
      expect(renamed.message, 'renamed');
      expect(list.where((s) => s.message.contains('second')), hasLength(1));
    });

    test('refuses a ref that is not a stash selector', () async {
      await write('a.txt', 'x\n');
      await g(['stash', 'push', '-q']);

      await expectLater(
        writer().stashRename('refs/stash', 'x'),
        throwsA(isA<GitException>()),
      );
      expect(await reader().stashes(), hasLength(1));
    });
  });

  group('stashBranch', () {
    test('checks out a branch at the base with the stash applied', () async {
      await write('a.txt', 'stashed\n');
      await g(['stash', 'push', '-q']);
      final base = await out(['rev-parse', 'HEAD']);
      await write('b.txt', 'moved on\n');
      await g(['commit', '-q', '-am', 'later']);

      await writer().stashBranch('from-stash', 'stash@{0}');

      expect(await out(['branch', '--show-current']), 'from-stash');
      expect(await out(['rev-parse', 'HEAD']), base);
      expect(await read('a.txt'), 'stashed\n');
      expect(await reader().stashes(), isEmpty, reason: 'git drops it');
    });
  });
}
