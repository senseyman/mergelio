import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

/// Staging, unstaging and discarding a picked set of files: exactly those
/// files move, and a discard of the set is one undoable step.
void main() {
  late Directory repo;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: repo.path)).stdout.trim();

  File file(String name) => File('${repo.path}/$name');

  Future<Map<String, WorkingFile>> status() async => {
    for (final f in await GitReader(svc, repo.path).status()) f.path: f,
  };

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_multisel_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    for (final n in ['a.txt', 'b.txt', 'c.txt', 'old.txt']) {
      await file(n).writeAsString('committed $n\n');
    }
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    await file('a.txt').writeAsString('edit a\n');
    await file('b.txt').writeAsString('staged b\n');
    await g(['add', 'b.txt']);
    await file('b.txt').writeAsString('staged b, then more\n');
    await file('c.txt').writeAsString('edit c\n');
    await g(['mv', 'old.txt', 'renamed.txt']);
    await file('new.txt').writeAsString('brand new\n');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('stageFiles stages only the picked files', () async {
    final actions = container().read(repoActionsProvider(repo.path));
    await actions.stageFiles(['a.txt', 'new.txt']);
    final s = await status();
    expect(s['a.txt']!.isStaged, isTrue);
    expect(s['new.txt']!.isStaged, isTrue);
    expect(s['c.txt']!.isStaged, isFalse);
  });

  test('unstageFiles unstages only the picked files', () async {
    final actions = container().read(repoActionsProvider(repo.path));
    await g(['add', 'a.txt', 'c.txt']);
    await actions.unstageFiles(['a.txt', 'b.txt']);
    final s = await status();
    expect(s['a.txt']!.isStaged, isFalse);
    expect(s['b.txt']!.isStaged, isFalse);
    expect(s['c.txt']!.isStaged, isTrue);
  });

  test('a bulk stage is refused while another op holds the repo', () async {
    final c = container();
    c.read(busyProvider.notifier).state = const BusyState('Pull');
    await c.read(repoActionsProvider(repo.path)).stageFiles(['a.txt']);
    expect((await status())['a.txt']!.isStaged, isFalse);
  });

  group('discardFiles', () {
    Future<List<WorkingFile>> picked(List<String> paths) async {
      final s = await status();
      return [for (final p in paths) s[p]!];
    }

    test('reverts tracked files, deletes untracked, leaves the rest', () async {
      final actions = container().read(repoActionsProvider(repo.path));
      await actions.discardFiles(await picked(['a.txt', 'b.txt', 'new.txt']));

      expect(await file('a.txt').readAsString(), 'committed a.txt\n');
      expect(await file('b.txt').readAsString(), 'committed b.txt\n');
      expect(await file('new.txt').exists(), isFalse);
      expect(await file('c.txt').readAsString(), 'edit c\n');
      expect(await out(['diff', '--cached', '--name-only']), 'renamed.txt');
    });

    test('a staged rename goes back to its old name', () async {
      final actions = container().read(repoActionsProvider(repo.path));
      await actions.discardFiles(await picked(['renamed.txt']));

      expect(await file('old.txt').readAsString(), 'committed old.txt\n');
      expect(await file('renamed.txt').exists(), isFalse);
      expect(await out(['diff', '--cached', '--name-only']), 'b.txt');
    });

    test('is one undo entry that restores work and index', () async {
      final c = container();
      final actions = c.read(repoActionsProvider(repo.path));
      await actions.discardFiles(
        await picked(['a.txt', 'b.txt', 'new.txt', 'renamed.txt']),
      );
      expect(c.read(undoProvider(repo.path)).past.length, 1);

      await actions.undo();

      expect(await file('a.txt').readAsString(), 'edit a\n');
      expect(await file('b.txt').readAsString(), 'staged b, then more\n');
      expect(await file('new.txt').readAsString(), 'brand new\n');
      expect(await file('renamed.txt').readAsString(), 'committed old.txt\n');
      expect(await file('old.txt').exists(), isFalse);
      final cached = await out(['diff', '--cached', '--name-status', '-M']);
      expect(cached, contains('b.txt'));
      expect(cached, contains('R100\told.txt\trenamed.txt'));
      expect(await out(['show', ':b.txt']), 'staged b');
    });

    test('redo discards again', () async {
      final actions = container().read(repoActionsProvider(repo.path));
      await actions.discardFiles(await picked(['a.txt', 'new.txt']));
      await actions.undo();
      await actions.redo();

      expect(await file('a.txt').readAsString(), 'committed a.txt\n');
      expect(await file('new.txt').exists(), isFalse);
    });

    test('a file named like a glob snapshots only itself', () async {
      await file('*.txt').writeAsString('committed star\n');
      await g(['add', '--', ':(literal)*.txt']);
      // Only the star file: b.txt's staged change has to stay staged.
      await g(['commit', '-q', '-m', 'star', '--', ':(literal)*.txt']);
      await file('*.txt').writeAsString('staged star\n');
      await g(['add', '--', ':(literal)*.txt']);
      final actions = container().read(repoActionsProvider(repo.path));

      await actions.discardFiles(await picked(['*.txt']));
      // b.txt's staged change was never discarded, so undo must not try to
      // stage it a second time.
      await actions.undo();

      expect(await out(['show', ':*.txt']), 'staged star');
      expect(await out(['show', ':b.txt']), 'staged b');
    });

    test('an empty pick records nothing', () async {
      final c = container();
      await c.read(repoActionsProvider(repo.path)).discardFiles(const []);
      expect(c.read(undoProvider(repo.path)).canUndo, isFalse);
    });
  });
}
