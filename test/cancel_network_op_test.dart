// A network operation that stalls on an unreachable remote would otherwise
// hold its lane until the five-minute timeout. The busy state carries a way to
// kill the git process, so the user gets the app back immediately — and an
// abandoned op reports itself as cancelled, not as a failure.
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
  /// completed, standing in for a remote that stopped answering.
  Completer<void> hold(String command) => _gates[command] = Completer<void>();

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
    // A killed child never returns a result; the service turns that into a
    // cancellation rather than a failure.
    if (cancel?.isCancelled ?? false) {
      throw GitCancelledException('git ${args.first} cancelled');
    }
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

  test('a running fetch offers a way to abandon it', () async {
    final gate = git.hold('fetch');
    final running = actions.fetch();
    await pumpEventQueue();

    expect(container.read(fetchBusyProvider)?.onCancel, isNotNull);

    gate.complete();
    await running;
  });

  test('a running push offers a way to abandon it', () async {
    final gate = git.hold('push');
    final running = actions.push();
    await pumpEventQueue();

    expect(container.read(busyProvider)?.onCancel, isNotNull);

    gate.complete();
    await running;
  });

  test('cancelling frees the lane', () async {
    final gate = git.hold('fetch');
    final running = actions.fetch();
    await pumpEventQueue();

    container.read(fetchBusyProvider)!.onCancel!();
    gate.complete();
    await running;

    expect(container.read(fetchBusyProvider), isNull);
  });

  test('a cancelled operation reports cancelled, not failed', () async {
    final gate = git.hold('fetch');
    final running = actions.fetch();
    await pumpEventQueue();

    container.read(fetchBusyProvider)!.onCancel!();
    gate.complete();
    await running;

    final toast = container.read(toastProvider).last;
    expect(toast.title, 'Fetch cancelled');
    expect(toast.kind, isNot(ToastKind.error));
  });

  test('a background fetch stays silent when it is cancelled', () async {
    final gate = git.hold('fetch');
    final running = actions.fetch(silent: true);
    await pumpEventQueue();

    container.read(fetchBusyProvider)!.onCancel!();
    gate.complete();
    await running;

    expect(container.read(toastProvider), isEmpty);
  });

  test(
    'an operation that was never cancelled carries no cancel after it',
    () async {
      await actions.fetch();

      expect(container.read(fetchBusyProvider), isNull);
      expect(container.read(toastProvider).last.title, 'Fetch complete');
    },
  );
}
