import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/line_history.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  GitReader reader() => GitReader(svc, dir.path);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_linehist_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 'm@e.com']);
    await g(['config', 'user.name', 'Maria']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/f.txt').writeAsString('one\ntwo\nthree\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'add f']);
    // A pure rename, then an edit confined to line 2. `git log -L` walks
    // through the rename on its own, so the range's history reaches back to
    // the file's original name.
    await g(['mv', 'f.txt', 'g.txt']);
    await g(['commit', '-q', '-m', 'rename to g']);
    await File('${dir.path}/g.txt').writeAsString('one\nTWO\nthree\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'edit line two']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('GitReader.lineHistory', () {
    test('walks the range back through a rename', () async {
      final entries = await reader().lineHistory('g.txt', 2, 2);
      expect(entries.map((e) => e.commit.message), ['edit line two', 'add f']);
      // The oldest entry predates the rename, so it reports the old path.
      expect(entries.last.path, 'f.txt');
    });

    test('carries the range diff for each commit', () async {
      final entries = await reader().lineHistory('g.txt', 2, 2);
      final hunk = entries.first.hunks.single;
      expect(
        hunk.lines.where((l) => l.type == DiffLineType.del).map((l) => l.text),
        ['two'],
      );
      expect(
        hunk.lines.where((l) => l.type == DiffLineType.add).map((l) => l.text),
        ['TWO'],
      );
    });

    test('omits commits that left the range untouched', () async {
      final entries = await reader().lineHistory('g.txt', 2, 2);
      expect(
        entries.map((e) => e.commit.message),
        isNot(contains('rename to g')),
      );
    });

    test('reads a multi-line range', () async {
      final entries = await reader().lineHistory('g.txt', 1, 3);
      expect(entries.map((e) => e.commit.message), ['edit line two', 'add f']);
    });

    test('returns nothing for a range past the end of the file', () async {
      expect(await reader().lineHistory('g.txt', 90, 99), isEmpty);
    });

    test('resolves the range against an explicit revision', () async {
      // Two commits back the file still had its original name, and the edit to
      // line 2 has not happened yet.
      final entries = await reader().lineHistory('f.txt', 2, 2, rev: 'HEAD~2');
      expect(entries.map((e) => e.commit.message), ['add f']);
    });
  });

  group('parseLineHistory', () {
    // One record: NUL, then the seven header fields, then the range patch.
    String record({
      required String sha,
      required String subject,
      required String patch,
    }) =>
        '\x00$sha\x1f${sha}0\x1fMaria\x1fm@e.com\x1f'
        '2026-09-06T12:00:00+01:00\x1f\x1f$subject\x1f$patch';

    test('splits records on the NUL that opens each header', () {
      final raw =
          record(
            sha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            subject: 'second',
            patch:
                'diff --git a/g.txt b/g.txt\n'
                '--- a/g.txt\n+++ b/g.txt\n@@ -2,1 +2,1 @@\n-two\n+TWO\n',
          ) +
          record(
            sha: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            subject: 'first',
            patch:
                'diff --git a/f.txt b/f.txt\n'
                '--- /dev/null\n+++ b/f.txt\n@@ -0,0 +2,1 @@\n+two\n',
          );

      final entries = parseLineHistory(raw);

      expect(entries.map((e) => e.commit.message), ['second', 'first']);
      expect(entries.map((e) => e.path), ['g.txt', 'f.txt']);
      expect(entries.first.hunks.single.header, '@@ -2,1 +2,1 @@');
    });

    test('keeps a field separator that occurs inside the patch', () {
      final raw = record(
        sha: 'cccccccccccccccccccccccccccccccccccccccc',
        subject: 'unit separator in source',
        patch:
            'diff --git a/g.txt b/g.txt\n'
            '--- a/g.txt\n+++ b/g.txt\n@@ -1,1 +1,1 @@\n-a\n+a\x1fb\n',
      );

      final entries = parseLineHistory(raw);

      expect(
        entries.single.hunks.single.lines
            .where((l) => l.type == DiffLineType.add)
            .map((l) => l.text),
        ['a\x1fb'],
      );
    });

    test('reads commit metadata off the header fields', () {
      final entries = parseLineHistory(
        record(
          sha: 'dddddddddddddddddddddddddddddddddddddddd',
          subject: 'metadata',
          patch:
              'diff --git a/g.txt b/g.txt\n'
              '--- a/g.txt\n+++ b/g.txt\n@@ -1,1 +1,1 @@\n-a\n+b\n',
        ),
      );

      final c = entries.single.commit;
      expect(c.sha, 'dddddddddddddddddddddddddddddddddddddddd');
      expect(c.author, 'Maria');
      expect(c.authorEmail, 'm@e.com');
      expect(c.date, DateTime.parse('2026-09-06T12:00:00+01:00'));
    });

    test('returns nothing for empty output', () {
      expect(parseLineHistory(''), isEmpty);
    });
  });
}
