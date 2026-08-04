// Which commits touched one path. Read from git rather than from the loaded
// commits, since a commit list carries no file names.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/path_history.dart';

class _FakeGit implements GitService {
  final GitResult result;
  final calls = <List<String>>[];
  _FakeGit(this.result);

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add(a);
    return result;
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  ProviderContainer container(_FakeGit git) {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the shas git reports for the path are returned', () async {
    final git = _FakeGit(const GitResult(0, 'aaa\nbbb\nccc\n', ''));
    final c = container(git);

    final shas = await c.read(
      pathHistoryProvider(const PathKey('/r', 'lib/main.dart')).future,
    );

    expect(shas, {'aaa', 'bbb', 'ccc'});
  });

  test('the path is passed as a path, never as a revision', () async {
    final git = _FakeGit(const GitResult(0, '', ''));
    final c = container(git);

    await c.read(
      pathHistoryProvider(const PathKey('/r', 'lib/main.dart')).future,
    );

    final args = git.calls.single;
    expect(args.first, 'log');
    expect(args.last, 'lib/main.dart');
    expect(args[args.length - 2], '--');
  });

  test('a failed read reports nothing rather than throwing', () async {
    final git = _FakeGit(const GitResult(128, '', 'fatal: bad path'));
    final c = container(git);

    expect(
      await c.read(pathHistoryProvider(const PathKey('/r', 'x')).future),
      isEmpty,
    );
  });

  test('history for a real file follows the file through a rename', () async {
    const svc = SystemGitService();
    final repo = await Directory.systemTemp.createTemp('mergelio_pathlog_');
    addTearDown(() async {
      if (await repo.exists()) await repo.delete(recursive: true);
    });
    Future<void> g(List<String> args) async {
      final r = await svc.run(args, repoPath: repo.path);
      if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }

    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${repo.path}/old.txt').writeAsString('one\n');
    await File('${repo.path}/other.txt').writeAsString('other\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'first']);
    await g(['mv', 'old.txt', 'new.txt']);
    await g(['commit', '-q', '-am', 'rename']);
    await File('${repo.path}/other.txt').writeAsString('changed\n');
    await g(['commit', '-q', '-am', 'unrelated']);

    final c = ProviderContainer();
    addTearDown(c.dispose);

    final shas = await c.read(
      pathHistoryProvider(PathKey(repo.path, 'new.txt')).future,
    );

    // The rename and the commit that first added the file, not the unrelated
    // one.
    expect(shas, hasLength(2));
  });
}
