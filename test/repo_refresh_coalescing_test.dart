import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';

/// Creating a branch and checking it out is one gesture but two operations, and
/// each one asks the graph to reload. Reading the repository twice for that is
/// pure waste — on a repository with many branches the second read is seconds
/// of squash-link inference that the first read already did.
/// Counts how often the repository is actually read. Watching the provider's
/// emissions cannot do that: a reload started while another is in flight
/// supersedes it, so two reads of the repository still surface as one value.
/// The ref signature is read exactly once per read of the repository, and its
/// command is distinctive, which makes it the honest count.
class _CountingGit implements GitService {
  final GitService _inner;
  var refReads = 0;

  _CountingGit(this._inner);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) {
    if (args.length == 2 &&
        args.first == 'for-each-ref' &&
        args[1] == '--format=%(objectname) %(refname)') {
      refReads++;
    }
    return _inner.run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
    );
  }

  @override
  Future<String> version() => _inner.version();

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);
}

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_coalesce_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.txt').writeAsString('1\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'A']);
  });

  tearDown(() async => dir.delete(recursive: true));

  test('a branch created and checked out reads the repository once', () async {
    final git = _CountingGit(svc);
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);

    // A listener keeps the provider alive, so an invalidation really does
    // rebuild it rather than being dropped as unobserved.
    c.listen(repoDataProvider(dir.path), (_, _) {}, fireImmediately: true);
    await c.read(repoDataProvider(dir.path).future);
    git.refReads = 0;

    final actions = c.read(repoActionsProvider(dir.path));
    await actions.createBranch('feature');
    await actions.checkout('feature');

    await Future<void>.delayed(actionSettle * 6);
    final data = await c.read(repoDataProvider(dir.path).future);

    expect(
      git.refReads,
      1,
      reason: 'two operations, one read of the repository',
    );
    expect(
      data.branches.firstWhere((b) => b.current).name,
      'feature',
      reason: 'the single read still reflects both operations',
    );
  });
}
