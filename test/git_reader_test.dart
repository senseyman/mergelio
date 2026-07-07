import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';

/// Integration tests: build a real repository with the system `git` binary and
/// read it back through [GitReader].
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) {
      throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }
  }

  Future<void> write(String name, String content) =>
      File('${dir.path}/$name').writeAsString(content);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_reader_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);

    await write('a.txt', '1\n');
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'A']);

    await g(['checkout', '-q', '-b', 'feature']);
    await write('b.txt', 'b\n');
    await g(['add', 'b.txt']);
    await g(['commit', '-q', '-m', 'B on feature']);

    await g(['checkout', '-q', 'main']);
    await write('a.txt', '2\n');
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'C on main']);

    await g(['merge', '--no-ff', '-m', 'Merge feature', 'feature']);
    await g(['tag', 'v1.0']);

    // Working-tree state: one staged add, one unstaged modify, one untracked.
    await write('d.txt', 'd\n');
    await g(['add', 'd.txt']);
    await write('a.txt', '3\n');
    await write('e.txt', 'untracked\n');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  GitReader reader() => GitReader(svc, dir.path);

  test('reads commits with a two-parent merge and ref decoration', () async {
    final commits = await reader().commits();
    expect(commits, isNotEmpty);

    final merge = commits.firstWhere((c) => c.merge);
    expect(merge.parents.length, 2);
    expect(merge.message, 'Merge feature');

    final hasMainHead = commits.any(
      (c) => c.refs.any((r) => r.kind == RefKind.local && r.name == 'main'),
    );
    expect(hasMainHead, isTrue);
  });

  test('assignLanes places the merge and gives it mergeFrom', () async {
    final laned = assignLanes(await reader().commits());
    final merge = laned.firstWhere((c) => c.merge);
    expect(merge.mergeFrom, isNotNull);
    expect(laned.any((c) => c.lane > 0), isTrue);
  });

  test('reads local branches with current flag', () async {
    final branches = await reader().branches();
    final names = branches.map((b) => b.name).toSet();
    expect(names, containsAll(<String>['main', 'feature']));
    expect(branches.firstWhere((b) => b.name == 'main').current, isTrue);
    expect(branches.firstWhere((b) => b.name == 'feature').current, isFalse);
  });

  test('reads tags', () async {
    expect(await reader().tags(), contains('v1.0'));
  });

  test('parses staged, unstaged and untracked working files', () async {
    final files = {for (final f in await reader().status()) f.path: f};

    expect(files['d.txt']?.isStaged, isTrue);
    expect(files['a.txt']?.isUnstaged, isTrue);
    expect(files['e.txt']?.isUntracked, isTrue);
  });
}
