// Discarding the diff of a file that was deleted in the working tree. The
// patch is reverse-applied, so it has to describe the file as gone — otherwise
// git looks for it to read the pre-image and stops at "No such file or
// directory".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/stage_patch.dart';

const _svc = SystemGitService();

void main() {
  late Directory repo;
  late GitWriter writer;

  Future<void> git(List<String> args) async {
    final r = await _svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> diffOf(String path) async {
    final r = await _svc.run(['diff', '--', path], repoPath: repo.path);
    return r.stdout;
  }

  File file(String name) => File('${repo.path}/$name');

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_discard_del_');
    writer = GitWriter(_svc, repo.path);
    await git(['init', '-q', '-b', 'main']);
    await git(['config', 'user.email', 't@e.com']);
    await git(['config', 'user.name', 'Tester']);
    await git(['config', 'commit.gpgsign', 'false']);
    await file('notes.txt').writeAsString('one\ntwo\nthree\n');
    await git(['add', 'notes.txt']);
    await git(['commit', '-q', '-m', 'add notes']);
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('discarding the hunk of a deleted file brings the file back', () async {
    await file('notes.txt').delete();
    final diff = parseUnifiedDiff(await diffOf('notes.txt')).single;

    final patch = buildDiscardPatch(diff, 0, null);

    expect(patch, isNotNull);
    await writer.applyToWorktree(patch!, reverse: true);
    expect(await file('notes.txt').readAsString(), 'one\ntwo\nthree\n');
  });

  test('the patch says the file is gone rather than pointing at it', () async {
    await file('notes.txt').delete();
    final diff = parseUnifiedDiff(await diffOf('notes.txt')).single;

    final patch = buildDiscardPatch(diff, 0, null)!;

    expect(patch, contains('+++ /dev/null'));
    expect(patch, isNot(contains('+++ b/notes.txt')));
  });

  test('discarding some of a deleted file restores only those lines', () async {
    await file('notes.txt').delete();
    final diff = parseUnifiedDiff(await diffOf('notes.txt')).single;

    // The hunk is three deletions; take back the first and the last.
    final patch = buildDiscardPatch(diff, 0, {0, 2})!;
    await writer.applyToWorktree(patch, reverse: true);

    expect(await file('notes.txt').readAsString(), 'one\nthree\n');
  });

  test('undoing that discard deletes the file again', () async {
    await file('notes.txt').delete();
    final diff = parseUnifiedDiff(await diffOf('notes.txt')).single;
    final patch = buildDiscardPatch(diff, 0, null)!;
    await writer.applyToWorktree(patch, reverse: true);

    // Undo re-applies the patch forward, which is the deletion again.
    await writer.applyToWorktree(patch);

    expect(await file('notes.txt').exists(), isFalse);
  });

  test('an executable file comes back executable', () async {
    // Restoring at the wrong mode leaves a script git reports as modified and
    // the shell refuses to run.
    await file('run.sh').writeAsString('#!/bin/sh\necho hi\n');
    await git(['update-index', '--add', '--chmod=+x', 'run.sh']);
    await git(['commit', '-q', '-m', 'add script']);
    await file('run.sh').delete();
    final diff = parseUnifiedDiff(await diffOf('run.sh')).single;

    await writer.applyToWorktree(
      buildDiscardPatch(diff, 0, null)!,
      reverse: true,
    );

    final status = await _svc.run([
      'status',
      '--porcelain',
      '--',
      'run.sh',
    ], repoPath: repo.path);
    expect(status.stdout.trim(), isEmpty);
  });

  test('a modified file is still described as the file it is', () async {
    await file('notes.txt').writeAsString('one\ntwo\nfour\n');
    final diff = parseUnifiedDiff(await diffOf('notes.txt')).single;

    final patch = buildDiscardPatch(diff, 0, null)!;

    expect(patch, contains('+++ b/notes.txt'));
    await writer.applyToWorktree(patch, reverse: true);
    expect(await file('notes.txt').readAsString(), 'one\ntwo\nthree\n');
  });
}
