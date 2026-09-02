import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
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
import 'package:mergelio/ui/workspace/branch_switch.dart';

class _FakeGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    // 'status --porcelain' looks clean so the switch path stays linear.
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}

ProviderContainer _container(
  _FakeGit git,
  RepoData data, {
  bool confirm = false,
  Map<String, Worktree> heldBranches = const {},
}) => ProviderContainer(
  overrides: [
    gitServiceProvider.overrideWithValue(git),
    settingsProvider.overrideWith(
      (ref) => SettingsController(
        InMemorySettingsRepository(),
        AppSettings(confirmDestructive: confirm),
      ),
    ),
    repoDataProvider('/r').overrideWith((ref) async => data),
    worktreeByBranchProvider('/r').overrideWithValue(heldBranches),
  ],
);

void main() {
  group('remoteSwitchIsDestructive', () {
    const rb = RemoteBranch(
      remote: 'origin',
      branch: 'main',
      hasLocal: true,
      tip: 'bbb',
    );

    test('false when there is no local branch', () {
      expect(
        remoteSwitchIsDestructive(
          const RemoteBranch(remote: 'origin', branch: 'main', tip: 'bbb'),
          const [],
        ),
        isFalse,
      );
    });

    test('false when the local tip equals the remote tip', () {
      expect(
        remoteSwitchIsDestructive(rb, const [Branch(name: 'main', tip: 'bbb')]),
        isFalse,
      );
    });

    test('true when the local tip differs from the remote tip', () {
      expect(
        remoteSwitchIsDestructive(rb, const [Branch(name: 'main', tip: 'aaa')]),
        isTrue,
      );
    });
  });

  group('resolveBranchChip', () {
    const remotes = [
      RemoteBranch(remote: 'origin', branch: 'main', hasLocal: true, tip: 'x'),
    ];

    test('a remote label resolves to the remote branch', () {
      final r = resolveBranchChip('origin/main', remotes);
      expect(r.remote, remotes.first);
      expect(r.local, isNull);
    });

    test('a non-remote label resolves to a local target', () {
      final r = resolveBranchChip('main', remotes);
      expect(r.local, 'main');
      expect(r.remote, isNull);
    });
  });

  group('activateBranch', () {
    Future<List<List<String>>> run(
      WidgetTester tester,
      RepoData data, {
      String? local,
      RemoteBranch? remote,
      bool confirm = false,
      bool tapConfirm = false,
      bool tapCancel = false,
    }) async {
      final git = _FakeGit();
      final c = _container(git, data, confirm: confirm);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppTokens.dark()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (ctx, ref, _) => TextButton(
                onPressed: () => activateBranch(
                  ref,
                  ctx,
                  '/r',
                  localBranch: local,
                  remote: remote,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      if (tapConfirm) {
        await tester.pump();
        await tester.tap(find.text('Reset & switch'));
      }
      if (tapCancel) {
        await tester.pump();
        await tester.tap(find.text('Cancel'));
      }
      await tester.pumpAndSettle();
      return git.calls;
    }

    testWidgets('diverged remote, confirm on, cancelled → no reset', (
      tester,
    ) async {
      final calls = await run(
        tester,
        const RepoData(
          branches: [Branch(name: 'main', tip: 'aaa')],
        ),
        remote: const RemoteBranch(
          remote: 'origin',
          branch: 'main',
          hasLocal: true,
          tip: 'bbb',
        ),
        confirm: true,
        tapCancel: true,
      );
      expect(calls.any((a) => a.contains('--hard')), isFalse);
    });

    testWidgets('local target → checkout', (tester) async {
      final calls = await run(tester, const RepoData(), local: 'dev');
      expect(
        calls.any((a) => a.first == 'checkout' && a.contains('dev')),
        isTrue,
      );
    });

    testWidgets('remote with no local → tracking checkout', (tester) async {
      final calls = await run(
        tester,
        const RepoData(),
        remote: const RemoteBranch(remote: 'origin', branch: 'feat', tip: 'x'),
      );
      expect(calls.any((a) => a.contains('--track')), isTrue);
    });

    testWidgets('remote with equal local tip → plain checkout, no reset', (
      tester,
    ) async {
      final calls = await run(
        tester,
        const RepoData(
          branches: [Branch(name: 'main', tip: 'x')],
        ),
        remote: const RemoteBranch(
          remote: 'origin',
          branch: 'main',
          hasLocal: true,
          tip: 'x',
        ),
      );
      expect(
        calls.any((a) => a.first == 'checkout' && a.contains('main')),
        isTrue,
      );
      expect(calls.any((a) => a.contains('--hard')), isFalse);
    });

    testWidgets('diverged remote, confirm off → resets to remote', (
      tester,
    ) async {
      final calls = await run(
        tester,
        const RepoData(
          branches: [Branch(name: 'main', tip: 'aaa')],
        ),
        remote: const RemoteBranch(
          remote: 'origin',
          branch: 'main',
          hasLocal: true,
          tip: 'bbb',
        ),
        confirm: false,
      );
      expect(
        calls.any((a) => a.contains('--hard') && a.contains('origin/main')),
        isTrue,
      );
    });

    testWidgets('diverged remote, confirm on → dialog, confirm resets', (
      tester,
    ) async {
      final calls = await run(
        tester,
        const RepoData(
          branches: [Branch(name: 'main', tip: 'aaa')],
        ),
        remote: const RemoteBranch(
          remote: 'origin',
          branch: 'main',
          hasLocal: true,
          tip: 'bbb',
        ),
        confirm: true,
        tapConfirm: true,
      );
      expect(calls.any((a) => a.contains('--hard')), isTrue);
    });
  });

  group('activateBranch: collision guard', () {
    Future<(List<List<String>>, ProviderContainer)> run(
      WidgetTester tester, {
      String? local = 'feat/x',
      RemoteBranch? remote,
      RepoData data = const RepoData(),
      bool confirm = false,
      required Worktree holder,
      String heldBranch = 'feat/x',
      List<String> taps = const [],
    }) async {
      final git = _FakeGit();
      final c = _container(
        git,
        data,
        confirm: confirm,
        heldBranches: {heldBranch: holder},
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppTokens.dark()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (ctx, ref, _) => TextButton(
                onPressed: () => activateBranch(
                  ref,
                  ctx,
                  '/r',
                  localBranch: remote == null ? local : null,
                  remote: remote,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      for (final label in taps) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      return (git.calls, c);
    }

    testWidgets('a branch held elsewhere shows the collision dialog', (
      tester,
    ) async {
      await run(
        tester,
        holder: const Worktree(path: '/other', branch: 'feat/x'),
      );
      expect(find.text('Checkout anyway'), findsOneWidget);
    });

    testWidgets('cancel leaves the branch untouched', (tester) async {
      final (calls, _) = await run(
        tester,
        holder: const Worktree(path: '/other', branch: 'feat/x'),
        taps: const ['Cancel'],
      );
      expect(calls.any((a) => a.first == 'checkout'), isFalse);
    });

    testWidgets('checkout anyway checks out with the override flag', (
      tester,
    ) async {
      final (calls, _) = await run(
        tester,
        holder: const Worktree(path: '/other', branch: 'feat/x'),
        taps: const ['Checkout anyway'],
      );
      expect(calls.last, ['checkout', '--ignore-other-worktrees', 'feat/x']);
    });

    testWidgets('open worktree switches tabs instead of checking out', (
      tester,
    ) async {
      final (calls, c) = await run(
        tester,
        holder: const Worktree(path: '/other', branch: 'feat/x'),
        taps: const ['Open worktree'],
      );
      expect(calls.any((a) => a.first == 'checkout'), isFalse);
      expect(c.read(workspaceProvider).activeTab?.path, '/other');
    });

    testWidgets('a branch held by this repo is not a collision', (
      tester,
    ) async {
      final (calls, _) = await run(
        tester,
        holder: const Worktree(path: '/r', branch: 'feat/x'),
      );
      expect(calls.last, ['checkout', 'feat/x']);
    });

    testWidgets(
      'a remote target whose equal-tip local is held elsewhere shows the '
      'collision dialog instead of an immediate checkout',
      (tester) async {
        final (calls, _) = await run(
          tester,
          data: const RepoData(
            branches: [Branch(name: 'main', tip: 'x')],
          ),
          remote: const RemoteBranch(
            remote: 'origin',
            branch: 'main',
            hasLocal: true,
            tip: 'x',
          ),
          holder: const Worktree(path: '/other', branch: 'main'),
          heldBranch: 'main',
        );
        expect(find.text('Checkout anyway'), findsOneWidget);
        expect(calls.any((a) => a.first == 'checkout'), isFalse);
      },
    );

    testWidgets(
      'checkout anyway on a remote target with equal-tip local checks out '
      'with the override flag, no reset',
      (tester) async {
        final (calls, _) = await run(
          tester,
          data: const RepoData(
            branches: [Branch(name: 'main', tip: 'x')],
          ),
          remote: const RemoteBranch(
            remote: 'origin',
            branch: 'main',
            hasLocal: true,
            tip: 'x',
          ),
          holder: const Worktree(path: '/other', branch: 'main'),
          heldBranch: 'main',
          taps: const ['Checkout anyway'],
        );
        expect(calls.last, ['checkout', '--ignore-other-worktrees', 'main']);
        expect(calls.any((a) => a.contains('--hard')), isFalse);
      },
    );

    testWidgets(
      'a diverged remote target whose local is held elsewhere shows the '
      'collision dialog before the destructive-reset confirmation',
      (tester) async {
        final (calls, _) = await run(
          tester,
          data: const RepoData(
            branches: [Branch(name: 'main', tip: 'aaa')],
          ),
          remote: const RemoteBranch(
            remote: 'origin',
            branch: 'main',
            hasLocal: true,
            tip: 'bbb',
          ),
          confirm: true,
          holder: const Worktree(path: '/other', branch: 'main'),
          heldBranch: 'main',
        );
        // The collision dialog shows first; the destructive-reset
        // confirmation has not appeared yet, and nothing has been reset.
        expect(find.text('Checkout anyway'), findsOneWidget);
        expect(find.text('Reset & switch'), findsNothing);
        expect(calls.any((a) => a.contains('--hard')), isFalse);
      },
    );

    testWidgets(
      'checkout anyway on a diverged, held-elsewhere remote target then '
      'confirming the reset resets with the override flag',
      (tester) async {
        final (calls, _) = await run(
          tester,
          data: const RepoData(
            branches: [Branch(name: 'main', tip: 'aaa')],
          ),
          remote: const RemoteBranch(
            remote: 'origin',
            branch: 'main',
            hasLocal: true,
            tip: 'bbb',
          ),
          confirm: true,
          holder: const Worktree(path: '/other', branch: 'main'),
          heldBranch: 'main',
          taps: const ['Checkout anyway', 'Reset & switch'],
        );
        expect(
          calls.any((a) => a.contains('--hard') && a.contains('origin/main')),
          isTrue,
        );
        expect(
          calls.any(
            (a) =>
                a.first == 'checkout' &&
                a.contains('--ignore-other-worktrees') &&
                a.contains('main'),
          ),
          isTrue,
        );
      },
    );
  });
}
