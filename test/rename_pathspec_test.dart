// A renamed file has two paths, and git only pairs them when the diff is asked
// for both. Limiting it to the new path alone makes git see a file that
// appeared from nowhere, so the whole file renders as added and the edit that
// came with the rename is lost.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';

void main() {
  late Directory repo;
  late GitReader reader;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_rename_');
    reader = GitReader(svc, repo.path);
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File(
      '${repo.path}/moved.txt',
    ).writeAsString('a\nb\nc\nd\ne\nf\ng\nh\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    await g(['checkout', '-q', '-b', 'feature']);
    await g(['mv', 'moved.txt', 'renamed.txt']);
    await File(
      '${repo.path}/renamed.txt',
    ).writeAsString('a\nb\nc\nd\ne\nf\ng\nZ\n');
    await g(['commit', '-qam', 'rename and edit']);
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('compareDiff of a rename shows the edit, not a fresh file', () async {
    final raw = await reader.compareDiff(
      'main',
      'feature',
      'renamed.txt',
      origPath: 'moved.txt',
    );

    expect(raw, contains('rename from moved.txt'));
    expect(raw, contains('-h'));
    expect(raw, contains('+Z'));
    expect(raw, isNot(contains('new file')));
  });

  test('commitDiff of a rename shows the edit, not a fresh file', () async {
    final sha = (await svc.run(['rev-parse', 'HEAD'], repoPath: repo.path)).out;

    final raw = await reader.commitDiff(
      sha,
      'renamed.txt',
      origPath: 'moved.txt',
    );

    expect(raw, contains('rename from moved.txt'));
    expect(raw, contains('+Z'));
    expect(raw, isNot(contains('new file')));
  });

  test('a plain path is unaffected by the rename handling', () async {
    final raw = await reader.compareDiff('main', 'feature', 'renamed.txt');

    expect(raw, isNotEmpty);
  });
}
