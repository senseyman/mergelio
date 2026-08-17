import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';

class _FakeGit implements GitService {
  int calls = 0;
  final argv = <List<String>>[];
  String stdout;
  _FakeGit(this.stdout);

  /// How many times the worktree list has actually been read from git — the
  /// refresh that follows a mutation issues plenty of other reads.
  int get listCalls => argv
      .where((a) => a.length >= 2 && a[0] == 'worktree' && a[1] == 'list')
      .length;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls++;
    argv.add(args);
    return GitResult(0, stdout, '');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

/// Fails with a plain, non-[GitException] error — a filesystem hiccup rather
/// than git refusing the command — to prove such failures are contained
/// rather than escaping uncaught into a UI callback.
class _ThrowingGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    throw StateError('disk unplugged');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

const _twoTrees =
    'worktree /r\nHEAD 1111111111111111111111111111111111111111\n'
    'branch refs/heads/main\n\n'
    'worktree /r-login\nHEAD 2222222222222222222222222222222222222222\n'
    'branch refs/heads/feat/login\n\n';

void main() {
  test('worktreesProvider parses and caches', () async {
    final git = _FakeGit(_twoTrees);
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);

    final first = await c.read(worktreesProvider('/r').future);
    expect(first.length, 2);
    await c.read(worktreesProvider('/r').future);
    expect(git.calls, 1, reason: 'second read served from cache');
  });

  test('invalidating refetches', () async {
    final git = _FakeGit(_twoTrees);
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);

    await c.read(worktreesProvider('/r').future);
    c.invalidate(worktreesProvider('/r'));
    await c.read(worktreesProvider('/r').future);
    expect(git.calls, 2);
  });

  test(
    'a mutation refreshes every open path, not just the acting one',
    () async {
      // Two tabs, two cached lists. Removing a worktree from one of them
      // changes what the other should show, so the sibling's cache has to be
      // dropped as well — otherwise its Worktrees section and branch badges go
      // on advertising an entry that no longer exists.
      final git = _FakeGit(_twoTrees);
      final c = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(c.dispose);

      await c.read(worktreesProvider('/r').future);
      await c.read(worktreesProvider('/r-login').future);
      expect(git.listCalls, 2);

      await c.read(repoActionsProvider('/r')).worktreeLock('/r-login');
      final afterMutation = git.listCalls;

      await c.read(worktreesProvider('/r').future);
      await c.read(worktreesProvider('/r-login').future);
      expect(
        git.listCalls - afterMutation,
        2,
        reason: 'both cached lists were dropped, so both refetched',
      );
    },
  );

  test('worktreeByBranchProvider maps branches to their holders', () async {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_FakeGit(_twoTrees))],
    );
    addTearDown(c.dispose);

    await c.read(worktreesProvider('/r').future);
    final map = c.read(worktreeByBranchProvider('/r'));
    expect(map['feat/login']?.path, '/r-login');
    expect(map['main']?.path, '/r');
    expect(map.containsKey('nope'), isFalse);
  });

  test('worktreeByBranchProvider is empty before the list resolves', () {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_FakeGit(_twoTrees))],
    );
    addTearDown(c.dispose);
    expect(c.read(worktreeByBranchProvider('/r')), isEmpty);
  });

  test('parseGitdirFile reads the pointer a linked worktree leaves', () {
    expect(
      parseGitdirFile('gitdir: /home/u/repo/.git/worktrees/login\n'),
      '/home/u/repo/.git/worktrees/login',
    );
    expect(parseGitdirFile('not a pointer'), isNull);
    expect(parseGitdirFile(''), isNull);
  });

  test('closeTabsAt closes every tab at that directory, however spelled', () {
    final c = WorkspaceController();
    c.openRepo('/home/u/repo');
    c.openRepo('/home/u/repo-login');
    expect(c.state.tabs.length, 2);

    c.closeTabsAt('/home/u/repo-login/');
    expect(c.state.tabs.length, 1);
    expect(c.state.tabs.single.path, '/home/u/repo');
  });

  test('openRepo reuses a tab whose path is spelled differently', () {
    // Git reports absolute, resolved paths; a tab opened from the directory
    // picker may carry a trailing separator. Opening one from the Worktrees
    // section must activate the existing tab, not add a second one for the
    // same checkout — everything keyed by repo path assumes one tab per repo.
    final c = WorkspaceController();
    final first = c.openRepo('/home/u/repo-login/');
    final again = c.openRepo('/home/u/repo-login');
    expect(c.state.tabs.length, 1);
    expect(again.id, first.id);
  });

  test('a moved worktree takes its tab with it', () async {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_FakeGit(_twoTrees))],
    );
    addTearDown(c.dispose);
    final ws = c.read(workspaceProvider.notifier);
    ws.openRepo('/r-login');
    ws.setOpenFiles('/r-login', ['/r-login/a.txt'], '/r-login/a.txt');

    await c
        .read(repoActionsProvider('/r'))
        .worktreeMove('/r-login', '/r-moved');

    final tab = c.read(workspaceProvider).tabs.single;
    expect(tab.path, '/r-moved', reason: 'the tab follows the directory');
    expect(tab.name, 'r-moved');
    expect(tab.openFiles, ['/r-moved/a.txt']);
    expect(tab.activeFile, '/r-moved/a.txt');
  });

  test('a failed move leaves the tab where it was', () async {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_ThrowingGit())],
    );
    addTearDown(c.dispose);
    c.read(workspaceProvider.notifier).openRepo('/r-login');

    await c
        .read(repoActionsProvider('/r'))
        .worktreeMove('/r-login', '/r-moved');

    expect(c.read(workspaceProvider).tabs.single.path, '/r-login');
  });

  test('closeTabsAt leaves unrelated tabs alone', () {
    final c = WorkspaceController();
    c.openRepo('/home/u/repo');
    c.closeTabsAt('/home/u/somewhere-else');
    expect(c.state.tabs.length, 1);
  });

  test(
    'worktreeAdd contains a non-git failure instead of letting it escape',
    () async {
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(_ThrowingGit())],
      );
      addTearDown(container.dispose);
      final actions = container.read(repoActionsProvider('/r'));

      final ok = await actions.worktreeAdd('/r-new', newBranch: 'feat/x');
      expect(ok, isFalse);
    },
  );

  test(
    'worktreeRemove contains a non-git failure instead of letting it escape',
    () async {
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(_ThrowingGit())],
      );
      addTearDown(container.dispose);
      final actions = container.read(repoActionsProvider('/r'));

      final message = await actions.worktreeRemove('/r-login');
      expect(message, isNotNull);
    },
  );

  test(
    'worktreePrune contains a non-git failure instead of letting it escape',
    () async {
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(_ThrowingGit())],
      );
      addTearDown(container.dispose);
      final actions = container.read(repoActionsProvider('/r'));

      expect(await actions.worktreePrune(), '');
      expect(await actions.worktreePrune(dryRun: true), '');
    },
  );
}
