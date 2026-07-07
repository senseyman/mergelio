import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out;

  Future<void> commit(String file, String msg) async {
    await File('${dir.path}/$file').writeAsString('$msg\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', msg]);
  }

  GitReader reader() => GitReader(svc, dir.path);
  GitWriter writer() => GitWriter(svc, dir.path);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_refops_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await commit('a.txt', 'A');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('create, rename, checkout and delete a branch', () async {
    await writer().createBranch('feature');
    expect(
      (await reader().branches()).map((b) => b.name),
      containsAll(['main', 'feature']),
    );

    await writer().renameBranch('feature', 'feat2');
    expect((await reader().branches()).map((b) => b.name), contains('feat2'));

    await writer().checkout('feat2');
    expect(
      (await reader().branches()).firstWhere((b) => b.name == 'feat2').current,
      isTrue,
    );

    await writer().checkout('main');
    await writer().deleteBranch('feat2', force: true);
    expect(
      (await reader().branches()).map((b) => b.name),
      isNot(contains('feat2')),
    );
  });

  test('create a branch at a specific commit', () async {
    final firstSha = await out(['rev-parse', 'HEAD']);
    await commit('b.txt', 'B');
    await writer().createBranch('back', at: firstSha);
    expect(await out(['rev-parse', 'back']), firstSha);
  });

  test('create, push-less, and delete a tag', () async {
    await writer().createTag('v1.0', message: 'release');
    expect(await reader().tags(), contains('v1.0'));
    await writer().deleteTag('v1.0');
    expect(await reader().tags(), isNot(contains('v1.0')));
  });

  test('cherry-pick copies a commit onto the current branch', () async {
    await writer().createBranch('feature');
    await writer().checkout('feature');
    await commit('c.txt', 'C on feature');
    final pick = await out(['rev-parse', 'HEAD']);

    await writer().checkout('main');
    await writer().cherryPick(pick);
    expect(File('${dir.path}/c.txt').existsSync(), isTrue);
    expect(await out(['log', '-1', '--format=%s']), 'C on feature');
  });

  test('revert adds an inverse commit', () async {
    await commit('d.txt', 'add d');
    final sha = await out(['rev-parse', 'HEAD']);
    await writer().revert(sha);
    expect(File('${dir.path}/d.txt').existsSync(), isFalse);
    expect(await out(['log', '-1', '--format=%s']), startsWith('Revert'));
  });

  test('reset --hard moves the branch and discards changes', () async {
    final base = await out(['rev-parse', 'HEAD']);
    await commit('e.txt', 'E');
    await writer().resetHard(base);
    expect(await out(['rev-parse', 'HEAD']), base);
    expect(File('${dir.path}/e.txt').existsSync(), isFalse);
  });

  test('stash push, apply and drop with re-store', () async {
    await File('${dir.path}/a.txt').writeAsString('dirty\n');
    await writer().stashPush(message: 'wip');
    expect(await reader().stashes(), isNotEmpty);
    // Working tree clean after stashing.
    expect(await reader().status(), isEmpty);

    await writer().stashApply('stash@{0}');
    expect(await reader().status(), isNotEmpty);

    final dropped = await writer().stashDrop('stash@{0}');
    expect(await reader().stashes(), isEmpty);

    // Undo: re-store the dropped stash.
    await writer().stashStore(dropped);
    expect(await reader().stashes(), isNotEmpty);
  });
}
