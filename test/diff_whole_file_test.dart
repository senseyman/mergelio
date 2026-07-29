import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/stage_patch.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/diff_target.dart';

/// Whole-file diff view: the reader takes a context-line count, the target
/// carries the choice, and the provider threads it through.
void main() {
  late Directory repo;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  // A file long enough that a 3-line context window cannot reach both ends.
  String body(String line20) =>
      [for (var i = 1; i <= 40; i++) i == 20 ? line20 : 'line $i'].join('\n');

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_wholefile_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${repo.path}/x.txt').writeAsString('${body('line 20')}\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    await File('${repo.path}/x.txt').writeAsString('${body('CHANGED')}\n');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  group('DiffTarget', () {
    test('wholeFile distinguishes equality and hashCode', () {
      const a = DiffTarget(repoPath: '/r', path: 'x.txt');
      const b = DiffTarget(repoPath: '/r', path: 'x.txt', wholeFile: true);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('withWholeFile flips only that flag', () {
      const a = DiffTarget(repoPath: '/r', path: 'x.txt', staged: true);
      final b = a.withWholeFile(true);
      expect(b.wholeFile, isTrue);
      expect(b.staged, isTrue);
      expect(b.repoPath, '/r');
      expect(b.path, 'x.txt');
      expect(b.withWholeFile(false), a);
    });

    test('withStaged preserves wholeFile', () {
      const a = DiffTarget(repoPath: '/r', path: 'x.txt', wholeFile: true);
      expect(a.withStaged(true).wholeFile, isTrue);
    });
  });

  group('GitReader context lines', () {
    test('workingDiff defaults to git\'s narrow context', () async {
      final raw = await GitReader(svc, repo.path).workingDiff('x.txt');
      expect(raw, contains('CHANGED'));
      expect(raw, isNot(contains('line 1\n')));
      expect(raw, isNot(contains('line 40')));
    });

    test('workingDiff with a large context returns the whole file', () async {
      final raw = await GitReader(
        svc,
        repo.path,
      ).workingDiff('x.txt', context: kWholeFileContext);
      expect(raw, contains('CHANGED'));
      expect(raw, contains('line 1\n'));
      expect(raw, contains('line 40'));
    });

    test('stagedDiff honours the context count', () async {
      await g(['add', 'x.txt']);
      final raw = await GitReader(
        svc,
        repo.path,
      ).stagedDiff('x.txt', context: kWholeFileContext);
      expect(raw, contains('line 1\n'));
      expect(raw, contains('line 40'));
    });

    test('commitDiff honours the context count', () async {
      await g(['add', 'x.txt']);
      await g(['commit', '-q', '-m', 'change']);
      final sha = (await svc.run([
        'rev-parse',
        'HEAD',
      ], repoPath: repo.path)).stdout.trim();
      final raw = await GitReader(
        svc,
        repo.path,
      ).commitDiff(sha, 'x.txt', context: kWholeFileContext);
      expect(raw, contains('line 1\n'));
      expect(raw, contains('line 40'));
    });
  });

  test('a line staged out of a whole-file hunk applies to the index', () async {
    // The whole-file view is one enormous hunk; the patch built from a single
    // line inside it must still be something `git apply --cached` accepts.
    final reader = GitReader(svc, repo.path);
    final file = parseUnifiedDiff(
      await reader.workingDiff('x.txt', context: kWholeFileContext),
    ).single;
    final changed = [
      for (var i = 0; i < file.hunks.single.lines.length; i++)
        if (file.hunks.single.lines[i].type != DiffLineType.context) i,
    ];
    final patch = buildStagePatch(
      file,
      0,
      lineIndexes: changeLineGroup(file.hunks.single.lines, changed.first),
    );
    expect(patch, isNotNull);

    await GitWriter(svc, repo.path).applyToIndex(patch!);

    final staged = await reader.stagedDiff('x.txt');
    expect(staged, contains('CHANGED'));
  });

  group('diffDocumentProvider', () {
    Future<List<String>> lines({required bool wholeFile}) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final doc = await c.read(
        diffDocumentProvider(
          DiffTarget(repoPath: repo.path, path: 'x.txt', wholeFile: wholeFile),
        ).future,
      );
      return [
        for (final f in doc.files)
          for (final h in f.hunks)
            for (final l in h.lines) l.text,
      ];
    }

    test('changes-only view omits the far ends of the file', () async {
      final out = await lines(wholeFile: false);
      expect(out, contains('CHANGED'));
      expect(out, isNot(contains('line 1')));
      expect(out, isNot(contains('line 40')));
    });

    test('whole-file view includes every line as one hunk', () async {
      final out = await lines(wholeFile: true);
      expect(out, contains('CHANGED'));
      expect(out, contains('line 1'));
      expect(out, contains('line 40'));
    });
  });
}
