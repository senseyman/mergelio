import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge_refresh.dart';
import 'package:mergelio/state/repo_actions.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  // Exit code the first 'fetch'/'pull'/'push' call answers with; anything
  // non-zero stands in for a remote that refused the operation.
  final int netExitCode;
  _FakeGit({this.netExitCode = 0});

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
    const netCommands = {'fetch', 'pull', 'push'};
    if (netExitCode != 0 && netCommands.contains(args.first)) {
      return GitResult(netExitCode, '', 'rejected');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Records every [refreshNow] call instead of running the real scheduler,
/// so a test can prove exactly when a mutation earns a forge refresh without
/// standing up settings, workspace and focus state the controller normally
/// depends on.
class _FakeForgeRefresh implements ForgeRefreshController {
  final List<String> refreshedPaths = [];

  @override
  void refreshNow(String path) => refreshedPaths.add(path);

  @override
  void refreshAfterGitOp(String path) => refreshedPaths.add(path);

  @override
  Duration? get scheduledInterval => null;

  @override
  Future<void>? get inFlightTick => null;

  @override
  Future<void> tick() async {}
}

void main() {
  test(
    'a mutation is blocked and warns while a network op is in flight',
    () async {
      final git = _FakeGit();
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(container.dispose);
      final actions = container.read(repoActionsProvider('/r'));

      // Simulate an op holding the repo.
      container.read(busyProvider.notifier).state = const BusyState('Pull');

      await actions.commit('nope');

      expect(git.calls.any((c) => c.first == 'commit'), isFalse);
      expect(
        container.read(toastProvider).any((t) => t.kind == ToastKind.warning),
        isTrue,
      );
    },
  );

  test('a mutation runs when nothing is in flight', () async {
    final git = _FakeGit();
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(container.dispose);
    final actions = container.read(repoActionsProvider('/r'));

    await actions.stageFile('a.txt');
    expect(git.calls.any((c) => c.first == 'add'), isTrue);
  });

  group('forge refresh on success', () {
    late _FakeForgeRefresh forge;

    ProviderContainer makeContainer(_FakeGit git) {
      final c = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          forgeRefreshProvider.overrideWithValue(forge),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() => forge = _FakeForgeRefresh());

    test('a fetch the user asked for refreshes the forge panel', () async {
      final actions = makeContainer(_FakeGit()).read(repoActionsProvider('/r'));

      await actions.fetch();

      expect(forge.refreshedPaths, ['/r']);
    });

    test(
      'a silent (background) fetch never refreshes the forge panel',
      () async {
        final actions = makeContainer(_FakeGit())
            .read(repoActionsProvider('/r'));

        await actions.fetch(silent: true);

        expect(forge.refreshedPaths, isEmpty);
      },
    );

    test('a failed fetch never refreshes the forge panel', () async {
      final actions = makeContainer(_FakeGit(netExitCode: 1))
          .read(repoActionsProvider('/r'));

      await actions.fetch();

      expect(forge.refreshedPaths, isEmpty);
    });

    test('a successful pull refreshes the forge panel', () async {
      final actions = makeContainer(_FakeGit()).read(repoActionsProvider('/r'));

      await actions.pull();

      expect(forge.refreshedPaths, ['/r']);
    });

    test('a failed pull never refreshes the forge panel', () async {
      final actions = makeContainer(_FakeGit(netExitCode: 1))
          .read(repoActionsProvider('/r'));

      await actions.pull();

      expect(forge.refreshedPaths, isEmpty);
    });

    test('a successful push refreshes the forge panel', () async {
      final actions = makeContainer(_FakeGit()).read(repoActionsProvider('/r'));

      await actions.push();

      expect(forge.refreshedPaths, ['/r']);
    });

    test('a failed push never refreshes the forge panel', () async {
      final actions = makeContainer(_FakeGit(netExitCode: 1))
          .read(repoActionsProvider('/r'));

      await actions.push();

      expect(forge.refreshedPaths, isEmpty);
    });
  });
}
