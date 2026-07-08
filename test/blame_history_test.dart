import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blame.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  GitReader reader() => GitReader(svc, dir.path);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_blame_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 'm@e.com']);
    await g(['config', 'user.name', 'Maria']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/f.txt').writeAsString('one\ntwo\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'add f']);
    // Rename (pure) then edit, in separate commits, so --follow detects the
    // rename and blame attributes lines to distinct commits.
    await g(['mv', 'f.txt', 'g.txt']);
    await g(['commit', '-q', '-m', 'rename to g']);
    await File('${dir.path}/g.txt').writeAsString('one\nTWO\nthree\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'edit g']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('fileHistory follows the rename', () async {
    final history = await reader().fileHistory('g.txt');
    expect(history.map((c) => c.message), ['edit g', 'rename to g', 'add f']);
  });

  test('blame annotates each line with its author', () async {
    final lines = parseBlame(await reader().blame('g.txt'));
    expect(lines.map((l) => l.content), ['one', 'TWO', 'three']);
    expect(lines.every((l) => l.author == 'Maria'), isTrue);
    expect(lines[0].sha, isNot(lines[1].sha)); // different commits
  });
}
