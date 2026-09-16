// A pull moves HEAD, so the cursor should land on the commit HEAD now points
// at: the action resolves HEAD once the pull settles and publishes it as the
// graph selection, which the graph view already flies to.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/repo_actions.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  // Exit code and stdout `git rev-parse --verify HEAD` answers with.
  final int headCode;
  final String headOut;
  // Whether the pull itself comes back refused (a conflict, say).
  final bool pullFails;
  _FakeGit({
    this.headCode = 0,
    this.headOut = 'newhead\n',
    this.pullFails = false,
  });

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
    if (args.first == 'pull' && pullFails) {
      return const GitResult(1, '', 'CONFLICT (content): merge conflict');
    }
    if (args.first == 'rev-parse' && args.contains('HEAD')) {
      return GitResult(headCode, headOut, '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  test('pull focuses the graph on the commit HEAD ended up at', () async {
    final git = _FakeGit();
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(container.dispose);
    container.read(selectedCommitProvider.notifier).state = 'stale';

    await container.read(repoActionsProvider('/r')).pull();

    expect(git.calls.any((c) => c.first == 'pull'), isTrue);
    expect(container.read(selectedCommitProvider), 'newhead');
  });

  test(
    'a pull that failed leaves the cursor where the reader left it',
    () async {
      final git = _FakeGit(pullFails: true);
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(container.dispose);
      container.read(selectedCommitProvider.notifier).state = 'reading-this';

      await container.read(repoActionsProvider('/r')).pull();

      expect(container.read(selectedCommitProvider), 'reading-this');
    },
  );

  test('pull leaves the selection alone on an unborn branch', () async {
    // `rev-parse --quiet --verify HEAD` exits non-zero with no output when the
    // branch has no commit yet; there is no row to focus.
    final git = _FakeGit(headCode: 1, headOut: '');
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(container.dispose);
    container.read(selectedCommitProvider.notifier).state = 'stale';

    await container.read(repoActionsProvider('/r')).pull();

    expect(container.read(selectedCommitProvider), 'stale');
  });
}
