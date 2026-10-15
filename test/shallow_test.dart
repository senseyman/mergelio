import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Records argument lists and timeouts, and reports success.
class _CapturingGit implements GitService {
  final calls = <List<String>>[];
  final timeouts = <Duration?>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    timeouts.add(timeout);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  const svc = SystemGitService();
  late Directory work;
  late String origin;

  Future<void> g(String dir, List<String> args) async {
    final r = await svc.run(args, repoPath: dir);
    if (!r.ok) throw StateError('git ${args.join(' ')}: ${r.err}');
  }

  setUp(() async {
    work = await Directory.systemTemp.createTemp('mergelio_shallow_');
    origin = '${work.path}/origin';
    Directory(origin).createSync();
    await g(origin, ['init', '-q', '-b', 'main']);
    await g(origin, ['config', 'user.email', 't@e.com']);
    await g(origin, ['config', 'user.name', 'T']);
    await g(origin, ['config', 'commit.gpgsign', 'false']);
    for (final n in ['1', '2', '3']) {
      await File('$origin/f$n').writeAsString('$n\n');
      await g(origin, ['add', '.']);
      await g(origin, ['commit', '-q', '-m', 'c$n']);
    }
  });

  tearDown(() async {
    if (await work.exists()) await work.delete(recursive: true);
  });

  Future<String> clone(List<String> extra) async {
    final target = '${work.path}/clone';
    await g(work.path, ['clone', '-q', ...extra, origin, target]);
    return target;
  }

  test('isShallow tells a shallow clone from a full one', () async {
    final full = await clone([]);
    expect(await GitReader(svc, full).isShallow(), isFalse);
    await Directory(full).delete(recursive: true);
    final shallow = await clone(['--no-local', '--depth', '1']);
    expect(await GitReader(svc, shallow).isShallow(), isTrue);
  });

  test(
    'singleBranchRemotes finds remotes a single-branch clone narrowed',
    () async {
      final repo = await clone([
        '--no-local',
        '--depth',
        '1',
        '--single-branch',
      ]);
      expect(await GitReader(svc, repo).singleBranchRemotes(), ['origin']);

      // A dotted name, as `remote rename` allows.
      await g(repo, ['remote', 'rename', 'origin', 'my.fork']);
      expect(await GitReader(svc, repo).singleBranchRemotes(), ['my.fork']);

      // Widened, or carrying a refspec of the user's own shape: left alone.
      await g(repo, ['remote', 'set-branches', 'my.fork', '*']);
      await g(repo, ['remote', 'add', 'other', origin]);
      await g(repo, [
        'config',
        '--replace-all',
        'remote.other.fetch',
        '+refs/heads/main:refs/remotes/elsewhere/main',
      ]);
      expect(await GitReader(svc, repo).singleBranchRemotes(), isEmpty);
    },
  );

  test('a remote with no fetch refspecs at all reads as none', () async {
    final repo = await clone([]);
    await g(repo, ['config', '--unset-all', 'remote.origin.fetch']);
    expect(await GitReader(svc, repo).singleBranchRemotes(), isEmpty);
  });

  test('unshallow fetches under a long ceiling', () async {
    final git = _CapturingGit();
    await GitWriter(git, '/r').unshallow();
    final i = git.calls.indexWhere((a) => a.contains('--unshallow'));
    expect(git.calls[i], ['fetch', '--unshallow']);
    expect(git.timeouts[i], const Duration(minutes: 30));
  });

  test('fetchFullHistory deepens a shallow clone to all of it', () async {
    final repo = await clone(['--no-local', '--depth', '1']);
    final c = ProviderContainer();
    addTearDown(c.dispose);

    final ok = await c.read(repoActionsProvider(repo)).fetchFullHistory();

    expect(ok, isTrue);
    expect(await GitReader(svc, repo).isShallow(), isFalse);
    final count = await svc.run([
      'rev-list',
      '--count',
      'HEAD',
    ], repoPath: repo);
    expect(count.out, '3');
    expect(c.read(toastProvider).last.kind, ToastKind.success);
  });

  test(
    'fetchFullHistory brings back the branches a single-branch clone left out',
    () async {
      await g(origin, ['branch', 'dev']);
      final repo = await clone([
        '--no-local',
        '--depth',
        '1',
        '--single-branch',
      ]);
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final ok = await c.read(repoActionsProvider(repo)).fetchFullHistory();

      expect(ok, isTrue);
      expect(await GitReader(svc, repo).isShallow(), isFalse);
      final remotes = await svc.run(['branch', '-r'], repoPath: repo);
      expect(remotes.out, contains('origin/dev'));
      expect(await GitReader(svc, repo).singleBranchRemotes(), isEmpty);
    },
  );

  test('fetchFullHistory on a full clone has nothing to do', () async {
    final repo = await clone([]);
    final c = ProviderContainer();
    addTearDown(c.dispose);

    final ok = await c.read(repoActionsProvider(repo)).fetchFullHistory();

    // git refuses --unshallow on a complete repository; it must not be asked.
    expect(ok, isTrue);
    expect(
      c.read(toastProvider).where((t) => t.kind == ToastKind.error),
      isEmpty,
    );
  });

  test('fetchFullHistory waits its turn behind a running fetch', () async {
    final repo = await clone(['--no-local', '--depth', '1']);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(fetchBusyProvider.notifier).state = const BusyState('Fetch');

    final ok = await c.read(repoActionsProvider(repo)).fetchFullHistory();

    expect(ok, isTrue);
    expect(c.read(toastProvider).last.kind, ToastKind.warning);
    expect(await GitReader(svc, repo).isShallow(), isTrue);
  });
}
