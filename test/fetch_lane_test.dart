// Fetching only ever contends with another fetch. It moves objects and
// remote-tracking refs, so a branch rename, a push or a commit has no reason to
// wait out the minutes one can take — and an auto-fetch tick must never be the
// thing that turns the user's own action away.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  final Map<String, Completer<void>> _gates = {};

  /// Makes later calls to [command] hang until the returned completer is
  /// completed, so a test can look at the app while an op is still in flight.
  Completer<void> hold(String command) => _gates[command] = Completer<void>();

  Iterable<List<String>> callsTo(String command) =>
      calls.where((c) => c.first == command);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    final gate = _gates[args.first];
    if (gate != null) await gate.future;
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _FakeGit git;
  late ProviderContainer container;
  late RepoActions actions;

  setUp(() {
    git = _FakeGit();
    container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(container.dispose);
    actions = container.read(repoActionsProvider('/r'));
  });

  /// Starts a fetch that stays in flight until the returned callback runs.
  Future<Future<void> Function()> startFetch() async {
    final gate = git.hold('fetch');
    final running = actions.fetch();
    await pumpEventQueue();
    return () async {
      gate.complete();
      await running;
    };
  }

  test('a fetch leaves the repository lane free', () async {
    final finish = await startFetch();

    expect(container.read(busyProvider), isNull);
    expect(container.read(fetchBusyProvider)?.label, 'Fetch');

    await finish();
  });

  test('a ref operation runs while a fetch is in flight', () async {
    final finish = await startFetch();

    await actions.renameBranch('old', 'new');

    expect(git.callsTo('branch'), isNotEmpty);
    expect(container.read(toastProvider), isEmpty);
    await finish();
  });

  test('a push runs while a fetch is in flight', () async {
    final finish = await startFetch();

    await actions.push();

    expect(git.callsTo('push'), isNotEmpty);
    await finish();
  });

  test('a second fetch is refused while one is in flight', () async {
    final finish = await startFetch();

    await actions.fetch();

    expect(git.callsTo('fetch').length, 1);
    expect(
      container.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
    await finish();
  });

  test('a silent fetch is refused without a toast', () async {
    final finish = await startFetch();

    await actions.fetch(silent: true);

    expect(git.callsTo('fetch').length, 1);
    expect(container.read(toastProvider), isEmpty);
    await finish();
  });

  test('pruning a remote waits for an in-flight fetch', () async {
    final finish = await startFetch();

    await actions.pruneRemote('origin');

    expect(git.callsTo('remote'), isEmpty);
    await finish();
  });

  test(
    'a fetch runs while a repository operation holds its own lane',
    () async {
      container.read(busyProvider.notifier).state = const BusyState('Merge');

      await actions.fetch();

      expect(git.callsTo('fetch'), isNotEmpty);
      // The rule that a refused op never clears someone else's slot holds in
      // this direction too: the merge must still own the repository lane.
      expect(container.read(busyProvider)?.label, 'Merge');
    },
  );

  test('the fetch lane clears once the fetch finishes', () async {
    final finish = await startFetch();
    await finish();

    expect(container.read(fetchBusyProvider), isNull);
  });
}
