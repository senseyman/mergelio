import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
  }) async {
    calls.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
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
}
