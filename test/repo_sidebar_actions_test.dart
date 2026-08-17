import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add(args);
    final out = switch (args.first) {
      'for-each-ref' when args.contains('refs/heads') =>
        'main\t*\t\nfeature\t\t\n',
      'rev-parse' => 'deadbeef\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Pumps [RepoSidebar] with the active repo open, optionally with
/// `worktreeByBranchProvider('/r')` overridden so a branch appears held by
/// another worktree.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeGit git, {
  Map<String, Worktree> heldBy = const {},
  RepoData? data,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
        worktreeByBranchProvider('/r').overrideWithValue(heldBy),
        if (data != null)
          repoDataProvider('/r').overrideWith((ref) async => data),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: RepoSidebar(onCollapse: () {})),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RepoSidebar)),
  );
  container.read(workspaceProvider.notifier).openRepo('/r');
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('double-clicking a branch checks it out', (tester) async {
    final git = _FakeGit();
    await _pump(tester, git);

    // The non-current branch is checkout-able via double-tap.
    final gesture = find.text('feature');
    expect(gesture, findsOneWidget);
    await tester.tap(gesture);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(gesture);
    await tester.pumpAndSettle();

    expect(
      git.calls.any((c) => c.first == 'checkout' && c.contains('feature')),
      isTrue,
    );
  });

  testWidgets('dragging a branch onto another opens the merge/rebase menu', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(tester, git);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('feature')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(find.text('main')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('Merge «feature» into «main»'), findsOneWidget);
    expect(find.textContaining('Rebase «feature» onto «main»'), findsOneWidget);
  });

  group('branches held by another worktree consult the collision guard', () {
    testWidgets('double-tap shows the dialog instead of checking out', (
      tester,
    ) async {
      final git = _FakeGit();
      await _pump(
        tester,
        git,
        heldBy: {'feature': const Worktree(path: '/other', branch: 'feature')},
      );

      final gesture = find.text('feature');
      await tester.tap(gesture);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(gesture);
      await tester.pumpAndSettle();

      expect(find.text('Checkout anyway'), findsOneWidget);
      expect(git.calls.any((c) => c.first == 'checkout'), isFalse);
    });

    testWidgets(
      'the context-menu Checkout item shows the dialog instead of checking out',
      (tester) async {
        final git = _FakeGit();
        await _pump(
          tester,
          git,
          heldBy: {
            'feature': const Worktree(path: '/other', branch: 'feature'),
          },
        );

        await tester.tapAt(
          tester.getCenter(find.text('feature')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Checkout'));
        await tester.pumpAndSettle();

        expect(find.text('Checkout anyway'), findsOneWidget);
        expect(git.calls.any((c) => c.first == 'checkout'), isFalse);
      },
    );

    testWidgets(
      'the remote-branch menu switch item shows the dialog instead of '
      'checking out',
      (tester) async {
        final git = _FakeGit();
        await _pump(
          tester,
          git,
          heldBy: {
            'feature': const Worktree(path: '/other', branch: 'feature'),
          },
          // A remote branch whose local counterpart exists: switching to it
          // checks out that local branch, which another worktree holds.
          data: const RepoData(
            branches: [Branch(name: 'main', current: true)],
            remotes: ['origin'],
            remoteBranches: [
              RemoteBranch(remote: 'origin', branch: 'feature', hasLocal: true),
            ],
          ),
        );

        await tester.tapAt(
          tester.getCenter(find.text('feature')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Switch to feature'));
        await tester.pumpAndSettle();

        expect(find.text('Checkout anyway'), findsOneWidget);
        expect(git.calls.any((c) => c.first == 'checkout'), isFalse);
      },
    );
  });
}
