import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/diff_target.dart';

void main() {
  late Directory repo;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_diffdoc_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${repo.path}/x.txt').writeAsString('one\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    // Stage line "two", then add an unstaged line "three" → partial stage.
    await File('${repo.path}/x.txt').writeAsString('one\ntwo\n');
    await g(['add', 'x.txt']);
    await File('${repo.path}/x.txt').writeAsString('one\ntwo\nthree\n');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  Future<String> body(bool staged) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final doc = await c.read(
      diffDocumentProvider(
        DiffTarget(repoPath: repo.path, path: 'x.txt', staged: staged),
      ).future,
    );
    final text = [
      for (final f in doc.files)
        for (final h in f.hunks) h.lines.map((l) => l.text).join('\n'),
    ].join('\n');
    return '$text|staged=${doc.staged}';
  }

  test(
    'staged side shows the staged change (two), not the unstaged (three)',
    () async {
      final out = await body(true);
      expect(out, contains('two'));
      expect(out, isNot(contains('three')));
      expect(out, contains('staged=true'));
    },
  );

  test('unstaged side shows the unstaged change (three)', () async {
    final out = await body(false);
    expect(out, contains('three'));
    expect(out, contains('staged=false'));
  });
}
