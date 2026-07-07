import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/diff_target.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> write(String name, String content) =>
      File('${dir.path}/$name').writeAsString(content);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_diffdoc_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await write('a.txt', 'one\ntwo\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'init']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('unstaged change is editable and not staged', () async {
    await write('a.txt', 'one\nTWO\n');
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final doc = await container.read(
      diffDocumentProvider(
        DiffTarget(repoPath: dir.path, path: 'a.txt'),
      ).future,
    );
    expect(doc.editable, isTrue);
    expect(doc.staged, isFalse);
    expect(doc.files.single.hunks, isNotEmpty);
  });

  test('a fully-staged file shows the staged view', () async {
    await write('a.txt', 'one\nTWO\n');
    await g(['add', 'a.txt']);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final doc = await container.read(
      diffDocumentProvider(
        DiffTarget(repoPath: dir.path, path: 'a.txt'),
      ).future,
    );
    expect(doc.editable, isTrue);
    expect(doc.staged, isTrue);
  });

  test('an untracked file shows its content as additions', () async {
    await write('new.txt', 'fresh1\nfresh2\n');
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final doc = await container.read(
      diffDocumentProvider(
        DiffTarget(repoPath: dir.path, path: 'new.txt'),
      ).future,
    );
    expect(doc.isEmpty, isFalse);
    final adds = doc.files
        .expand((f) => f.hunks)
        .expand((h) => h.lines)
        .where((l) => l.type == DiffLineType.add)
        .map((l) => l.text);
    expect(adds, containsAll(['fresh1', 'fresh2']));
  });

  test('a commit target is read-only', () async {
    final head = (await svc.run(['rev-parse', 'HEAD'], repoPath: dir.path)).out;
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final doc = await container.read(
      diffDocumentProvider(
        DiffTarget(repoPath: dir.path, path: 'a.txt', commitSha: head),
      ).future,
    );
    expect(doc.editable, isFalse);
  });
}
