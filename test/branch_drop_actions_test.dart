import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

void main() {
  late Directory dir;
  late ProviderContainer c;
  late RepoActions actions;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out.trim();

  Future<String> commit(String file, String content, String msg) async {
    await File('${dir.path}/$file').writeAsString(content);
    await g(['add', '.']);
    await g(['commit', '-q', '-m', msg]);
    return out(['rev-parse', 'HEAD']);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_bdrop_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    c = ProviderContainer();
    actions = c.read(repoActionsProvider(dir.path));
  });

  tearDown(() async {
    actions.dispose();
    c.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('isAncestor', () {
    test('is true only for a commit reachable from the other', () async {
      final a = await commit('a.txt', 'a\n', 'A');
      final b = await commit('b.txt', 'b\n', 'B');
      expect(await actions.isAncestor(a, b), isTrue);
      expect(await actions.isAncestor(b, a), isFalse);
    });
  });

  group('moveBranch', () {
    test('points another branch at a commit without checking it out, '
        'and undo puts it back', () async {
      final a = await commit('a.txt', 'a\n', 'A');
      await g(['branch', 'side']);
      final b = await commit('b.txt', 'b\n', 'B');

      await actions.moveBranch('side', b);

      expect(await out(['rev-parse', 'side']), b);
      expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'main');

      await actions.undo();
      expect(await out(['rev-parse', 'side']), a);
    });

    test('names a branch target in full in the undo label', () async {
      await commit('a.txt', 'a\n', 'A');
      await g(['branch', 'side']);
      await g(['branch', 'feature-long-name']);
      await commit('b.txt', 'b\n', 'B');

      await actions.moveBranch('side', 'main');

      expect(c.read(undoProvider(dir.path)).undoLabel, 'Move side to main');
      await actions.moveBranch('side', 'feature-long-name');
      expect(
        c.read(undoProvider(dir.path)).undoLabel,
        'Move side to feature-long-name',
      );
    });

    test('refuses the current branch, which needs a reset instead', () async {
      final a = await commit('a.txt', 'a\n', 'A');
      await commit('b.txt', 'b\n', 'B');

      await actions.moveBranch('main', a);

      expect(await out(['rev-parse', 'main']), isNot(a));
    });
  });

  group('fastForward', () {
    test('advances a branch that is not checked out', () async {
      await commit('a.txt', 'a\n', 'A');
      await g(['branch', 'behind']);
      final b = await commit('b.txt', 'b\n', 'B');

      await actions.fastForward('behind', 'main');

      expect(await out(['rev-parse', 'behind']), b);
      expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'main');
    });

    test('advances the current branch and its working tree', () async {
      await commit('a.txt', 'a\n', 'A');
      await g(['switch', '-q', '-c', 'ahead']);
      final b = await commit('b.txt', 'b\n', 'B');
      await g(['switch', '-q', 'main']);

      await actions.fastForward('main', 'ahead');

      expect(await out(['rev-parse', 'main']), b);
      expect(File('${dir.path}/b.txt').existsSync(), isTrue);
      await actions.undo();
      expect(await out(['rev-parse', 'main']), isNot(b));
    });

    test('leaves a diverged branch alone', () async {
      await commit('a.txt', 'a\n', 'A');
      await g(['switch', '-q', '-c', 'side']);
      final s = await commit('s.txt', 's\n', 'S');
      await g(['switch', '-q', 'main']);
      await commit('m.txt', 'm\n', 'M');

      await actions.fastForward('side', 'main');

      expect(await out(['rev-parse', 'side']), s);
    });
  });

  group('resetSoft', () {
    test('moves the branch and keeps the commits staged', () async {
      final a = await commit('a.txt', 'a\n', 'A');
      final b = await commit('b.txt', 'b\n', 'B');

      await actions.resetSoft(a);

      expect(await out(['rev-parse', 'HEAD']), a);
      expect(await out(['diff', '--cached', '--name-only']), 'b.txt');
      await actions.undo();
      expect(await out(['rev-parse', 'HEAD']), b);
    });
  });

  group('cherryPickOnto', () {
    test('switches to the branch and picks the commit onto it', () async {
      await commit('a.txt', 'a\n', 'A');
      await g(['branch', 'side']);
      final b = await commit('b.txt', 'b\n', 'B');

      await actions.cherryPickOnto('side', b);

      expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'side');
      expect(await out(['log', '-1', '--format=%s']), 'B');
      expect(File('${dir.path}/b.txt').existsSync(), isTrue);
    });
  });
}
