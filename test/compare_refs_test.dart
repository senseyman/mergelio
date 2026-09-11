import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';

void main() {
  late Directory repo;
  late GitReader reader;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> write(String path, String body) =>
      File('${repo.path}/$path').writeAsString(body);

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_compare_');
    reader = GitReader(svc, repo.path);
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await write('a.txt', 'one\n');
    await write('gone.txt', 'bye\n');
    await write('moved.txt', 'a\nb\nc\nd\ne\nf\ng\nh\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    await g(['checkout', '-q', '-b', 'feature']);
    await write('a.txt', 'one\ntwo\n');
    await write('added.txt', 'new\n');
    await File('${repo.path}/gone.txt').delete();
    await g(['mv', 'moved.txt', 'renamed.txt']);
    await g(['add', '-A']);
    await g(['commit', '-q', '-m', 'work']);
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('compareFiles lists every change between two refs', () async {
    final files = await reader.compareFiles('main', 'feature');
    final byPath = {for (final f in files) f.path: f};

    expect(byPath['a.txt']!.change, GitChange.modified);
    expect(byPath['added.txt']!.change, GitChange.added);
    expect(byPath['gone.txt']!.change, GitChange.deleted);
    expect(byPath['renamed.txt']!.change, GitChange.renamed);
    expect(byPath['renamed.txt']!.origPath, 'moved.txt');
  });

  test('compareFiles takes the direction from the argument order', () async {
    final files = await reader.compareFiles('feature', 'main');
    final byPath = {for (final f in files) f.path: f};

    expect(byPath['added.txt']!.change, GitChange.deleted);
    expect(byPath['gone.txt']!.change, GitChange.added);
  });

  test('compareFiles accepts shas as well as ref names', () async {
    final from = (await svc.run([
      'rev-parse',
      'main',
    ], repoPath: repo.path)).out;
    final to = (await svc.run([
      'rev-parse',
      'feature',
    ], repoPath: repo.path)).out;

    final files = await reader.compareFiles(from, to);

    expect(files.map((f) => f.path), contains('added.txt'));
  });

  test('compareFiles on identical refs is empty', () async {
    expect(await reader.compareFiles('main', 'main'), isEmpty);
  });

  test('compareDiff renders one file between two refs', () async {
    final raw = await reader.compareDiff('main', 'feature', 'a.txt');

    expect(raw, contains('+two'));
    expect(raw, isNot(contains('added.txt')));
  });

  test('compareDiff widens to the whole file on request', () async {
    final raw = await reader.compareDiff(
      'main',
      'feature',
      'a.txt',
      context: kWholeFileContext,
    );

    expect(raw, contains(' one'));
    expect(raw, contains('+two'));
  });

  test('compareDiff of an unrelated path is empty, not an error', () async {
    expect(await reader.compareDiff('main', 'feature', 'a.txt~'), isEmpty);
  });

  test('compareFiles reports a bad ref as a failure', () async {
    expect(
      () => reader.compareFiles('main', 'no-such-ref'),
      throwsA(isA<GitException>()),
    );
  });
}
