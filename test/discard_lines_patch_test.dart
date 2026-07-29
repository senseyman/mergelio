import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/stage_patch.dart';

/// Discarding a run of lines reverse-applies a patch to the working tree, which
/// holds every change — not just the chosen ones. The patch therefore has to be
/// built against the working tree, unlike the staging patch which is built
/// against the index.
void main() {
  late Directory repo;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  File file(String name) => File('${repo.path}/$name');

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_discardlines_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await file('a.txt').writeAsString('keep\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    // Three additions in one hunk, so a run can be taken from the middle.
    await file('a.txt').writeAsString('keep\none\ntwo\nthree\n');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  Future<FileDiff> workingDiff() async => parseUnifiedDiff(
    await GitReader(svc, repo.path).workingDiff('a.txt'),
  ).single;

  /// Index of the line whose text is [text] within the hunk.
  int lineOf(FileDiff diff, String text) =>
      diff.hunks.single.lines.indexWhere((l) => l.text == text);

  test('discarding one added line leaves the others in place', () async {
    final diff = await workingDiff();
    final patch = buildDiscardPatch(diff, 0, {lineOf(diff, 'two')});
    expect(patch, isNotNull);

    await GitWriter(svc, repo.path).applyToWorktree(patch!, reverse: true);

    expect(await file('a.txt').readAsString(), 'keep\none\nthree\n');
  });

  test('discarding a run of added lines drops exactly that run', () async {
    final diff = await workingDiff();
    final patch = buildDiscardPatch(diff, 0, {
      lineOf(diff, 'one'),
      lineOf(diff, 'two'),
    });

    await GitWriter(svc, repo.path).applyToWorktree(patch!, reverse: true);

    expect(await file('a.txt').readAsString(), 'keep\nthree\n');
  });

  test('discarding a removed line brings it back on its own', () async {
    await file('b.txt').writeAsString('x\ny\nz\n');
    await g(['add', 'b.txt']);
    await g(['commit', '-q', '-m', 'three lines']);
    // Remove two of the three lines, then take back only the first removal.
    await file('b.txt').writeAsString('z\n');

    final diff = parseUnifiedDiff(
      await GitReader(svc, repo.path).workingDiff('b.txt'),
    ).single;
    final patch = buildDiscardPatch(diff, 0, {lineOf(diff, 'x')});

    await GitWriter(svc, repo.path).applyToWorktree(patch!, reverse: true);

    expect(await file('b.txt').readAsString(), 'x\nz\n');
  });

  test('a whole hunk still discards every change in it', () async {
    final diff = await workingDiff();
    final patch = buildDiscardPatch(diff, 0, null);

    await GitWriter(svc, repo.path).applyToWorktree(patch!, reverse: true);

    expect(await file('a.txt').readAsString(), 'keep\n');
  });

  test('a run taken out of an untracked file leaves the rest behind', () async {
    // Untracked content only shows up through --no-index, and the file is not
    // in the index at all, so the patch has to land on the working tree.
    await file('new.txt').writeAsString('one\ntwo\nthree\n');
    final diff = parseUnifiedDiff(
      await GitReader(svc, repo.path).untrackedDiff('new.txt'),
    ).single;
    final patch = buildDiscardPatch(diff, 0, {lineOf(diff, 'two')});

    await GitWriter(svc, repo.path).applyToWorktree(patch!, reverse: true);

    expect(await file('new.txt').readAsString(), 'one\nthree\n');
  });

  test('selecting nothing changeable yields no patch', () async {
    final diff = await workingDiff();
    expect(buildDiscardPatch(diff, 0, const <int>{}), isNull);
  });
}
