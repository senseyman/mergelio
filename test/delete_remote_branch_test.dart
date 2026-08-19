// Deleting a branch on a remote. `git push --delete` is a one-way door, so it
// records no undo entry — and the combined local+remote delete is two git
// commands, so it has to survive the local half landing while the push fails.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];

  /// Substring of the joined arguments → stderr, for calls that come back
  /// non-zero. Keying on a substring separates `rev-parse --verify` (does the
  /// branch still exist?) from the plain `rev-parse` that reads its tip.
  final Map<String, String> failures = {};

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
    final line = args.join(' ');
    for (final f in failures.entries) {
      if (line.contains(f.key)) return GitResult(1, '', f.value);
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

  /// Makes the "does the local branch still exist?" probe report it gone, as
  /// it would be after a successful `git branch -d`.
  void localBranchGone() => git.failures['rev-parse --verify'] = '';

  group('deleteRemoteBranch', () {
    test(
      'pushes a delete for the branch behind the remote-tracking ref',
      () async {
        await actions.deleteRemoteBranch(
          const RemoteBranch(remote: 'origin', branch: 'feature/x'),
        );

        expect(git.callsTo('push').single, [
          'push',
          'origin',
          '--delete',
          'feature/x',
        ]);
      },
    );

    test('records no undo entry', () async {
      await actions.deleteRemoteBranch(
        const RemoteBranch(remote: 'origin', branch: 'x'),
      );

      expect(container.read(undoProvider('/r')).canUndo, isFalse);
    });

    test("surfaces git's own message when the push is refused", () async {
      git.failures['push'] = 'remote ref does not exist';

      await actions.deleteRemoteBranch(
        const RemoteBranch(remote: 'origin', branch: 'x'),
      );

      final toast = container.read(toastProvider).last;
      expect(toast.kind, ToastKind.error);
      expect(toast.description, contains('remote ref does not exist'));
    });
  });

  group('deleteBranchAndRemote', () {
    test('drops the local ref first, then the remote one', () async {
      localBranchGone();

      await actions.deleteBranchAndRemote('feature', 'origin/feature');

      final ordered = git.calls
          .where((c) => c.first == 'branch' || c.first == 'push')
          .toList();
      expect(ordered, [
        ['branch', '-d', 'feature'],
        ['push', 'origin', '--delete', 'feature'],
      ]);
    });

    test('splits the upstream at the remote, not at every slash', () async {
      localBranchGone();

      await actions.deleteBranchAndRemote('feat/x', 'origin/feat/x');

      expect(git.callsTo('push').single, [
        'push',
        'origin',
        '--delete',
        'feat/x',
      ]);
    });

    test('leaves the remote alone when the local delete is refused', () async {
      git.failures['branch -d'] = "branch 'feature' is not fully merged";

      await actions.deleteBranchAndRemote('feature', 'origin/feature');

      expect(git.callsTo('push'), isEmpty);
    });

    test('reports what is left behind when the push fails', () async {
      localBranchGone();
      git.failures['push'] = 'permission denied';

      await actions.deleteBranchAndRemote('feature', 'origin/feature');

      final toast = container.read(toastProvider).last;
      expect(toast.kind, ToastKind.error);
      expect(toast.title, contains('origin/feature is still on the remote'));
      expect(toast.title, contains('feature'));
    });

    test('does nothing for an upstream with no remote prefix', () async {
      await actions.deleteBranchAndRemote('feature', 'feature');

      expect(git.calls, isEmpty);
    });

    test('keeps the local delete on the undo stack', () async {
      localBranchGone();

      await actions.deleteBranchAndRemote('feature', 'origin/feature');

      expect(
        container.read(undoProvider('/r')).undoLabel,
        'Delete branch feature',
      );
    });
  });
}
