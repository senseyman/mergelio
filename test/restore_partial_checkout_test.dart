import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// What a checkout stopped part-way leaves depends on how far git got. It
/// writes files first and the index after, in one locked swap, so a stop can
/// land on either side of that swap; both must come back clean.
void main() {
  late Directory dir;
  late String main, topic;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out.trim();

  Future<void> write(String file, String text) =>
      File('${dir.path}/$file').writeAsString('$text\n');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_restorepartial_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await write('changed.txt', 'main');
    await write('gone.txt', 'main');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    main = await out(['rev-parse', 'HEAD']);
    await g(['checkout', '-q', '-b', 'topic']);
    await write('changed.txt', 'topic');
    await write('added.txt', 'topic');
    await g(['rm', '-q', 'gone.txt']);
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'topic']);
    topic = await out(['rev-parse', 'HEAD']);
    await g(['checkout', '-q', 'main']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Files written as `topic` has them, HEAD still on `main`.
  Future<void> filesWritten() async {
    await write('changed.txt', 'topic');
    await write('added.txt', 'topic');
    await File('${dir.path}/gone.txt').delete();
  }

  test('stopped before the index was written', () async {
    await filesWritten();
    await GitWriter(svc, dir.path).restorePartialCheckout(main, topic);
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test('stopped after the index was written', () async {
    await filesWritten();
    await g(['read-tree', topic]);
    await GitWriter(svc, dir.path).restorePartialCheckout(main, topic);
    expect(await out(['status', '--porcelain']), isEmpty);
  });

  test('changes staged before the checkout stay staged', () async {
    // git carries staged work on paths the checkout does not touch.
    await write('mine.txt', 'mine');
    await g(['add', 'mine.txt']);
    await filesWritten();
    await GitWriter(svc, dir.path).restorePartialCheckout(main, topic);
    expect(await out(['status', '--porcelain']), 'A  mine.txt');
  });
}
