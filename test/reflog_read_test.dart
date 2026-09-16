import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';

/// Integration tests: drive a real repository through operations that leave
/// reflog entries, then read them back through [GitReader.reflog].
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) {
      throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }
  }

  Future<Directory> bareRepo() async {
    final d = await Directory.systemTemp.createTemp('mergelio_reflog_empty_');
    final r = await svc.run(['init', '-q'], repoPath: d.path);
    if (!r.ok) throw StateError('git init failed: ${r.err}');
    return d;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_reflog_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);

    await g(['commit', '--allow-empty', '-q', '-m', 'A']);
    await g(['commit', '--allow-empty', '-q', '-m', 'B']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  GitReader reader() => GitReader(svc, dir.path);

  test('reads HEAD reflog newest first, with positional selectors', () async {
    final entries = await reader().reflog();

    expect(entries.length, greaterThanOrEqualTo(2));
    expect(entries.take(2).map((e) => e.selector), ['HEAD@{0}', 'HEAD@{1}']);
    // Newest first: the second commit heads the list.
    expect(entries.first.detail, 'B');
    expect(entries.first.action, 'commit');
  });

  test('records the verb of the operation that moved HEAD', () async {
    final head = await svc.run(['rev-parse', 'HEAD~1'], repoPath: dir.path);
    await g(['reset', '--hard', '-q', head.out]);
    await g(['checkout', '-q', '-b', 'feature']);

    final entries = await reader().reflog();

    expect(entries[0].action, 'checkout');
    expect(entries[1].action, 'reset');
    expect(entries[2].action, 'commit');
  });

  test('every entry carries the sha HEAD pointed at', () async {
    final entries = await reader().reflog();
    final head = await svc.run(['rev-parse', 'HEAD'], repoPath: dir.path);

    expect(entries.first.sha, head.out);
    expect(entries.every((e) => e.sha.length == 40), isTrue);
  });

  test('entries carry the author identity git recorded', () async {
    final entries = await reader().reflog();

    expect(entries.first.author, 'Tester');
    expect(entries.first.email, 't@example.com');
  });

  test('maxCount caps how much of the reflog is read', () async {
    final entries = await reader().reflog(maxCount: 1);

    expect(entries, hasLength(1));
    expect(entries.single.selector, 'HEAD@{0}');
  });

  test('a repository with no commits yet has an empty reflog', () async {
    // An unborn HEAD makes `git log -g` exit non-zero. That is the state of
    // every freshly-initialised repo, not a failure worth surfacing.
    final empty = await bareRepo();
    addTearDown(() async {
      if (await empty.exists()) await empty.delete(recursive: true);
    });

    expect(await GitReader(svc, empty.path).reflog(), isEmpty);
  });
}
