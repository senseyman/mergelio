import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/stage_patch.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> write(String name, String content) =>
      File('${dir.path}/$name').writeAsString(content);

  GitReader reader() => GitReader(svc, dir.path);
  GitWriter writer() => GitWriter(svc, dir.path);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_writer_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await write('a.txt', 'l1\nl2\nl3\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'init']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'stageFile then unstageFile move a file in and out of the index',
    () async {
      await write('a.txt', 'l1\nCHANGED\nl3\n');
      await writer().stageFile('a.txt');
      var staged = {for (final f in await reader().status()) f.path: f};
      expect(staged['a.txt']?.isStaged, isTrue);

      await writer().unstageFile('a.txt');
      staged = {for (final f in await reader().status()) f.path: f};
      expect(staged['a.txt']?.isStaged, isFalse);
      expect(staged['a.txt']?.isUnstaged, isTrue);
    },
  );

  test('applyToIndex stages a single line via a built patch', () async {
    // Two separate changes; stage only the first.
    await write('a.txt', 'X1\nl2\nX3\n');
    final file = parseUnifiedDiff(await reader().workingDiff('a.txt')).single;

    // Change lines in the hunk: find the add for "X1".
    final hunk = file.hunks.single;
    final addX1 = hunk.lines.indexWhere(
      (l) => l.type == DiffLineType.add && l.text == 'X1',
    );
    final patch = buildStagePatch(file, 0, lineIndexes: {addX1});
    expect(patch, isNotNull);

    await writer().applyToIndex(patch!);

    final stagedDiff = await reader().stagedDiff('a.txt');
    expect(stagedDiff, contains('+X1'));
    expect(stagedDiff, isNot(contains('+X3')));

    // The other change remains unstaged.
    expect(await reader().workingDiff('a.txt'), contains('+X3'));
  });

  test(
    'staging a modified line replaces it in the index, no duplicate',
    () async {
      // Modify only line 2; stage that changed line via its pair group.
      await write('a.txt', 'l1\nCHANGED\nl3\n');
      final file = parseUnifiedDiff(await reader().workingDiff('a.txt')).single;
      final hunk = file.hunks.single;
      final addIdx = hunk.lines.indexWhere(
        (l) => l.type == DiffLineType.add && l.text == 'CHANGED',
      );
      final group = changeLineGroup(hunk.lines, addIdx);
      final patch = buildStagePatch(file, 0, lineIndexes: group);
      await writer().applyToIndex(patch!);

      final indexBlob = (await svc.run([
        'show',
        ':a.txt',
      ], repoPath: dir.path)).stdout;
      expect(
        indexBlob,
        'l1\nCHANGED\nl3\n',
      ); // replaced, not l1\nl2\nCHANGED...
    },
  );

  test('commit creates a commit and clears the staged file', () async {
    await write('a.txt', 'l1\nl2\nl3\nl4\n');
    await writer().stageFile('a.txt');
    await writer().commit('add l4', description: 'a body');

    expect(await reader().status(), isEmpty);
    final head = (await svc.run([
      'log',
      '-1',
      '--format=%s%n%b',
    ], repoPath: dir.path)).out;
    expect(head, contains('add l4'));
    expect(head, contains('a body'));
  });

  test('amend replaces the top commit', () async {
    final before = (await svc.run([
      'rev-parse',
      'HEAD',
    ], repoPath: dir.path)).out;
    await write('a.txt', 'l1\nl2\nl3\namended\n');
    await writer().stageFile('a.txt');
    await writer().commit('reworded', amend: true);

    final after = (await svc.run([
      'rev-parse',
      'HEAD',
    ], repoPath: dir.path)).out;
    expect(after, isNot(before));
    final count = (await svc.run([
      'rev-list',
      '--count',
      'HEAD',
    ], repoPath: dir.path)).out;
    expect(count, '1'); // amend did not add a commit
  });
}
