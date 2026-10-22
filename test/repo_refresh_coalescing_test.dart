import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

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

  /// The first word of every command started, in order.
  final started = <String>[];

  /// Added before every `checkout`, the way a slow CI runner or a large
  /// working tree stretches it past the settle window.
  final Duration checkoutDelay;

  /// Holds every `fetch` until completed: a remote that is slow to answer.
  Completer<void>? fetchGate;

  /// Added before every `checkout`'s opening read of the current branch:
  /// the action is under way, but has not written anything yet.
  final Duration headRefDelay;

  _CountingGit(
    this._inner, {
    this.checkoutDelay = Duration.zero,
    this.headRefDelay = Duration.zero,
  });

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) {
    if (args.isNotEmpty) started.add(args.first);
    if (args.length == 2 &&
        args.first == 'for-each-ref' &&
        args[1] == '--format=%(objectname) %(refname)') {
      refReads++;
    }
    final gate = fetchGate;
    if (args.isNotEmpty && args.first == 'fetch' && gate != null) {
      return gate.future.then((_) => const GitResult(0, '', ''));
    }
    final slow = switch (args) {
      ['checkout', ...] => checkoutDelay,
      ['rev-parse', '--abbrev-ref', 'HEAD'] => headRefDelay,
      _ => Duration.zero,
    };
    if (slow > Duration.zero) {
      return Future<void>.delayed(slow).then(
        (_) => _inner.run(
          args,
          repoPath: repoPath,
          timeout: timeout,
          environment: environment,
          cancel: cancel,
        ),
      );
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

  Future<void> createThenCheckout({
    Duration checkoutDelay = Duration.zero,
    Duration headRefDelay = Duration.zero,
  }) async {
    final git = _CountingGit(
      svc,
      checkoutDelay: checkoutDelay,
      headRefDelay: headRefDelay,
    );
    final c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);

    // A listener keeps the provider alive, so an invalidation really does
    // rebuild it rather than being dropped as unobserved.
    c.listen(repoDataProvider(dir.path), (_, _) {}, fireImmediately: true);
    await c.read(repoDataProvider(dir.path).future);
    // A checkout first asks whether LFS is in play. The two probes behind that
    // run once a session, and the app's own panels have run them long before
    // anyone checks out; cold here, they would stretch the gap between the two
    // operations on a host with git-lfs and not on one without.
    await c.read(lfsToolProvider.future);
    await c.read(gitVersionProvider.future);
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
  }

  test(
    'a branch created and checked out reads the repository once',
    () => createThenCheckout(),
  );

  test(
    'a checkout slower than the settle window still reads once',
    () => createThenCheckout(checkoutDelay: actionSettle * 3),
  );

  test(
    'so does one slow before it writes anything',
    () => createThenCheckout(headRefDelay: actionSettle * 3),
  );

  test('a fetch still on the network does not hold the view back', () async {
    final git = _CountingGit(svc)..fetchGate = Completer<void>();
    final c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(repoDataProvider(dir.path), (_, _) {}, fireImmediately: true);
    await c.read(repoDataProvider(dir.path).future);
    final actions = c.read(repoActionsProvider(dir.path));

    // A background fetch that will not finish during this test.
    final fetch = actions.fetch(silent: true);
    git.refReads = 0;
    await actions.createBranch('feature');
    await Future<void>.delayed(actionSettle * 6);

    expect(git.refReads, 1, reason: 'the branch shows without the fetch');

    git.fetchGate!.complete();
    await fetch;
  });

  test('a diff tool left open does not hold the view back', () async {
    // Beside the repository, not in it, so it is no change to the tree.
    final release = '${dir.path}.release';
    await g(['config', 'diff.tool', 'wait']);
    await g([
      'config',
      'difftool.wait.cmd',
      'while [ ! -f "$release" ]; do sleep 0.05; done',
    ]);
    await File('${dir.path}/a.txt').writeAsString('2\n');

    final git = _CountingGit(svc);
    final c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    Future<void>? tool;
    // Registered after the container's, so it runs first (teardowns run in
    // reverse): let the tool go, wait for the action to finish with the
    // container still alive, and take the file away — being outside the
    // repository, it would outlive the test.
    addTearDown(() async {
      await File(release).writeAsString('');
      await tool;
      await File(release).delete();
    });
    c.listen(repoDataProvider(dir.path), (_, _) {}, fireImmediately: true);
    await c.read(repoDataProvider(dir.path).future);
    final actions = c.read(repoActionsProvider(dir.path));

    // The user's window onto the change: open for as long as they look.
    tool = actions.openDifftool(DiffTarget(repoPath: dir.path, path: 'a.txt'));
    // Well short of the test's own 30s timeout, so this says what went wrong.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!git.started.contains('difftool')) {
      if (DateTime.now().isAfter(deadline)) {
        fail('git never started the diff tool');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    git.refReads = 0;
    await actions.stageFile('a.txt');
    // Well inside the 2s a held reload would wait.
    await Future<void>.delayed(actionSettle * 6);

    expect(git.refReads, 1, reason: 'the staged file shows at once');
  });
}
