import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

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
    dir = await Directory.systemTemp.createTemp('mergelio_merge_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await write('a.txt', 'base\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    // Diverge: feature and main edit the same line.
    await g(['checkout', '-q', '-b', 'feature']);
    await write('a.txt', 'feature\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'feature edit']);

    await g(['checkout', '-q', 'main']);
    await write('a.txt', 'main\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'main edit']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'conflicting merge exposes the conflicted file, resolve then commit',
    () async {
      // Merge conflicts → throws; the file is listed as conflicted.
      await expectLater(
        writer().merge('feature'),
        throwsA(isA<GitException>()),
      );
      final conflicts = await reader().conflictedFiles();
      expect(conflicts, ['a.txt']);

      // Parse and resolve to "theirs".
      final content = await File('${dir.path}/a.txt').readAsString();
      expect(hasConflictMarkers(content), isTrue);
      final parts = parseConflicts(content);
      final res = {
        for (var i = 0; i < parts.length; i++)
          if (parts[i] is ConflictHunk) i: Resolution.theirs,
      };
      final resolved = resolveConflicts(parts, res);
      await write('a.txt', resolved);
      await g(['add', 'a.txt']);
      // Committing with MERGE_HEAD still set is what makes it a merge commit.
      await writer().commit('Merge feature');

      // Merge commit created, tree resolved, no conflicts remain.
      expect(await reader().conflictedFiles(), isEmpty);
      final head = (await svc.run(['rev-parse', 'HEAD^2'], repoPath: dir.path));
      expect(head.ok, isTrue); // has a second parent → real merge commit
      expect(await File('${dir.path}/a.txt').readAsString(), 'feature\n');
    },
  );

  test('merge --abort restores the pre-merge state', () async {
    await expectLater(writer().merge('feature'), throwsA(isA<GitException>()));
    await writer().mergeAbort();
    expect(await reader().conflictedFiles(), isEmpty);
    expect(await File('${dir.path}/a.txt').readAsString(), 'main\n');
  });

  test('a clean merge creates a merge commit without conflicts', () async {
    // Fast-forward-free merge of a non-conflicting branch.
    await g(['checkout', '-q', '-b', 'other', 'main']);
    await write('b.txt', 'new file\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'add b']);
    await g(['checkout', '-q', 'main']);

    await writer().merge('other', noFf: true);
    expect(await reader().conflictedFiles(), isEmpty);
    expect(File('${dir.path}/b.txt').existsSync(), isTrue);
  });
}
