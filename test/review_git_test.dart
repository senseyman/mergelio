import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

void main() {
  late Directory repo;
  late GitReader reader;
  late GitWriter writer;
  const svc = SystemGitService();

  Future<String> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  Future<void> commit(String path, String body, String msg) async {
    await File('${repo.path}/$path').writeAsString(body);
    await g(['add', '-A']);
    await g(['commit', '-q', '-m', msg]);
  }

  // main: base → m1.   feature (from base): f1 → f2.
  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_review_');
    reader = GitReader(svc, repo.path);
    writer = GitWriter(svc, repo.path);
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await commit('a.txt', 'one\n', 'base');
    await g(['checkout', '-q', '-b', 'feature']);
    await commit('a.txt', 'one\ntwo\n', 'f1');
    await commit('b.txt', 'bee\n', 'f2');
    await g(['checkout', '-q', 'main']);
    await commit('m.txt', 'main only\n', 'm1');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('mergeBase is the commit both sides grew from', () async {
    final base = await g(['rev-parse', 'feature~2']);
    expect(await reader.mergeBase('main', 'feature'), base);
  });

  test('mergeBase is null for unrelated histories', () async {
    await g(['checkout', '-q', '--orphan', 'lonely']);
    await g(['rm', '-rq', '--cached', '.']);
    await commit('z.txt', 'z\n', 'root');
    expect(await reader.mergeBase('main', 'lonely'), isNull);
  });

  test('mergeBase throws for a revision git cannot resolve', () async {
    expect(
      () => reader.mergeBase('main', 'no-such-ref'),
      throwsA(isA<GitException>()),
    );
  });

  test('resolveCommit peels a tag and rejects an unknown name', () async {
    await g(['tag', '-a', '-m', 'v', 'v1', 'feature']);
    expect(await reader.resolveCommit('v1'), await g(['rev-parse', 'feature']));
    expect(
      () => reader.resolveCommit('no-such-ref'),
      throwsA(isA<GitException>()),
    );
  });

  test('aheadBehind counts each side of the fork', () async {
    final c = await reader.aheadBehind('main', 'feature');
    expect(c.ahead, 2);
    expect(c.behind, 1);
  });

  test('rangeCommits lists only what head adds, newest first', () async {
    final page = await reader.rangeCommits('main', 'feature');
    expect([for (final c in page.commits) c.message], ['f2', 'f1']);
    expect(page.truncated, isFalse);
  });

  test('rangeCommits reports a page cut short by the cap', () async {
    final page = await reader.rangeCommits('main', 'feature', maxCount: 1);
    expect([for (final c in page.commits) c.message], ['f2']);
    expect(page.truncated, isTrue);
  });

  test('three-dot files come from the merge base, not base\'s tip', () async {
    final mb = await reader.mergeBase('main', 'feature');
    final threeDot = await reader.compareFiles(mb!, 'feature');
    final twoDot = await reader.compareFiles('main', 'feature');
    expect({for (final f in threeDot) f.path}, {'a.txt', 'b.txt'});
    // Tip to tip also sees main's own file, as a deletion.
    expect({for (final f in twoDot) f.path}, {'a.txt', 'b.txt', 'm.txt'});
  });

  test('rangeDiff is one patch covering every file', () async {
    final mb = await reader.mergeBase('main', 'feature');
    final raw = await reader.rangeDiff(mb!, 'feature');
    expect(raw, contains('diff --git a/a.txt b/a.txt'));
    expect(raw, contains('diff --git a/b.txt b/b.txt'));
    expect(raw, isNot(contains('m.txt')));
  });

  test('blame and file history read the given revision', () async {
    final blame = await reader.blame('b.txt', rev: 'feature');
    expect(blame, contains('summary f2'));
    final history = await reader.fileHistory('a.txt', rev: 'feature');
    expect([for (final c in history) c.message], ['f1', 'base']);
    // On main, which is checked out, a.txt never saw f1.
    final onMain = await reader.fileHistory('a.txt');
    expect([for (final c in onMain) c.message], ['base']);
  });

  test('formatPatch emits one mail per commit of the range', () async {
    final text = await writer.formatPatch('main', 'feature');
    expect(
      RegExp(r'^From [0-9a-f]{40} ', multiLine: true).allMatches(text),
      hasLength(2),
    );
    expect(text, contains('Subject: [PATCH 1/2] f1'));
    expect(text, contains('Subject: [PATCH 2/2] f2'));
  });

  test('formatPatchToDir writes the files and returns their paths', () async {
    final out = await Directory.systemTemp.createTemp('mergelio_patches_');
    addTearDown(() => out.delete(recursive: true));
    final files = await writer.formatPatchToDir('main', 'feature', out.path);
    expect(files, hasLength(2));
    for (final f in files) {
      expect(File(f).existsSync(), isTrue, reason: f);
      expect(f, startsWith(out.path));
    }
    // Nothing about the repository changed.
    expect(await g(['status', '--porcelain']), isEmpty);
  });
}
