import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/compare_target.dart';
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
    repo = await Directory.systemTemp.createTemp('mergelio_cmpdoc_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${repo.path}/x.txt').writeAsString('one\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    await g(['checkout', '-q', '-b', 'feature']);
    await File('${repo.path}/x.txt').writeAsString('one\ntwo\n');
    await g(['commit', '-qam', 'second']);
    await File('${repo.path}/x.txt').writeAsString('one\ntwo\nthree\n');
    await g(['commit', '-qam', 'third']);

    // An uncommitted edit must not leak into a two-ref comparison.
    await File('${repo.path}/x.txt').writeAsString('one\ntwo\nthree\nfour\n');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  Future<DiffDoc> load(DiffTarget target) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c.read(diffDocumentProvider(target).future);
  }

  List<String> added(DiffDoc doc) => [
    for (final f in doc.files)
      for (final h in f.hunks)
        for (final l in h.lines)
          if (l.type == DiffLineType.add) l.text,
  ];

  List<String> allLines(DiffDoc doc) => [
    for (final f in doc.files)
      for (final h in f.hunks)
        for (final l in h.lines) l.text,
  ];

  test('a two-ref target spans both commits, not just the last one', () async {
    final doc = await load(
      CompareTarget(
        repoPath: repo.path,
        from: 'main',
        to: 'feature',
      ).fileTarget('x.txt'),
    );
    expect(added(doc), containsAll(<String>['two', 'three']));
    expect(added(doc), isNot(contains('four'))); // working tree stays out
  });

  test('a comparison is never editable', () async {
    final doc = await load(
      DiffTarget(
        repoPath: repo.path,
        path: 'x.txt',
        baseRev: 'main',
        commitSha: 'feature',
      ),
    );

    expect(doc.editable, isFalse);
    expect(doc.staged, isFalse);
  });

  test('the whole-file toggle still applies', () async {
    final doc = await load(
      DiffTarget(
        repoPath: repo.path,
        path: 'x.txt',
        baseRev: 'main',
        commitSha: 'feature',
        wholeFile: true,
      ),
    );
    expect(allLines(doc), contains('one')); // unchanged context is included
    expect(added(doc), contains('three'));
  });
}
