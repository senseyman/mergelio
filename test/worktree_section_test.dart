import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/workspace/worktrees_section.dart';

const _repoPath = '/home/u/repo';

final _trees = <Worktree>[
  const Worktree(path: _repoPath, branch: 'main', kind: WorktreeKind.main),
  const Worktree(path: '/home/u/repo-login', branch: 'feat/login'),
  const Worktree(
    path: '/home/u/repo-detached',
    head: 'abcdef1234567890',
    detached: true,
  ),
  const Worktree(
    path: '/home/u/repo-locked',
    branch: 'locked-branch',
    locked: true,
    lockReason: 'edited elsewhere',
  ),
  const Worktree(
    path: '/home/u/repo-gone',
    branch: 'gone-branch',
    prunable: true,
    prunableReason: 'directory no longer exists',
  ),
  const Worktree(path: '/home/u/repo.git', kind: WorktreeKind.bare),
];

Future<ProviderContainer> _pump(
  WidgetTester tester,
  List<Worktree> trees,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        worktreesProvider(_repoPath).overrideWith((ref) async => trees),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: WorktreesSection(repoPath: _repoPath)),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(WorktreesSection)),
  );
  container.read(workspaceProvider.notifier).openRepo(_repoPath);
  await tester.pumpAndSettle();
  return container;
}

/// Records every argv it is given. Any `worktree remove` without `--force`
/// fails the way git does on a dirty tree, so the two-stage escalation in
/// [WorktreesSection]'s row menu has something real to react to.
class _FakeGit implements GitService {
  final List<List<String>> calls = [];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    if (args case [
      'worktree',
      'remove',
      ...final rest,
    ] when !rest.contains('--force')) {
      return const GitResult(
        128,
        '',
        "fatal: '/home/u/repo-login' contains modified or untracked files, "
            'use --force',
      );
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Just the `git worktree <verb>` argv, in order — every successful mutation
/// also triggers a full repo-data reload, which would otherwise swamp the
/// assertions below with unrelated read commands.
List<List<String>> _worktreeCalls(_FakeGit git, String verb) => git.calls
    .where((c) => c.length >= 2 && c[0] == 'worktree' && c[1] == verb)
    .toList();

List<List<String>> _removeCalls(_FakeGit git) => _worktreeCalls(git, 'remove');

Future<ProviderContainer> _pumpWithGit(
  WidgetTester tester,
  List<Worktree> trees,
  GitService git,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        worktreesProvider(_repoPath).overrideWith((ref) async => trees),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
        gitServiceProvider.overrideWithValue(git),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: WorktreesSection(repoPath: _repoPath)),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(WorktreesSection)),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The `PopupMenuButton` at the end of the row whose layout `Row` also holds
/// [label] — there is exactly one such `Row` per worktree, so this reaches
/// the row's own menu rather than the section header's prune menu or another
/// row's.
Future<void> _openRowMenu(WidgetTester tester, String label) async {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  await tester.tap(
    find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
  );
  await tester.pumpAndSettle();
}

InkWell _inkWellFor(Finder textFinder) {
  return find
          .ancestor(of: textFinder, matching: find.byType(InkWell))
          .evaluate()
          .first
          .widget
      as InkWell;
}

void main() {
  /// This app only ships desktop builds, but tests default to the Android
  /// platform, which hides desktop-only widget behaviour. The override has
  /// to be undone inside the test body — the framework checks it before
  /// tearDown runs.
  Future<void> onDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('lists every worktree by branch name and marks the active one', (
    tester,
  ) async {
    await onDesktop(() async {
      await _pump(tester, _trees);

      expect(find.text('WORKTREES'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
      expect(find.text('feat/login'), findsOneWidget);
      expect(find.text('locked-branch'), findsOneWidget);
      expect(find.text('gone-branch'), findsOneWidget);
      expect(find.text('(this)'), findsOneWidget);
    });
  });

  testWidgets('a detached worktree shows its short head instead of a branch', (
    tester,
  ) async {
    await onDesktop(() async {
      await _pump(tester, _trees);

      expect(find.text('abcdef1'), findsOneWidget);
      expect(find.text('abcdef1234567890'), findsNothing);
    });
  });

  testWidgets('a locked worktree shows a lock icon with the reason tooltip', (
    tester,
  ) async {
    await onDesktop(() async {
      await _pump(tester, _trees);

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byIcon(Icons.lock_outline),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tooltip.message, 'edited elsewhere');
    });
  });

  testWidgets(
    'a prunable worktree shows a warning icon with the reason tooltip',
    (tester) async {
      await onDesktop(() async {
        await _pump(tester, _trees);

        expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
        final tooltip = tester.widget<Tooltip>(
          find
              .ancestor(
                of: find.byIcon(Icons.warning_amber_outlined),
                matching: find.byType(Tooltip),
              )
              .first,
        );
        expect(tooltip.message, 'directory no longer exists');
      });
    },
  );

  testWidgets('bare, prunable and the active worktree rows are not clickable', (
    tester,
  ) async {
    await onDesktop(() async {
      await _pump(tester, _trees);

      expect(_inkWellFor(find.text('(this)')).onTap, isNull);
      expect(_inkWellFor(find.text('repo.git')).onTap, isNull);
      expect(_inkWellFor(find.text('gone-branch')).onTap, isNull);
      // A regular, non-current, non-locked, non-prunable worktree stays
      // clickable.
      expect(_inkWellFor(find.text('feat/login')).onTap, isNotNull);
      expect(_inkWellFor(find.text('locked-branch')).onTap, isNotNull);
    });
  });

  testWidgets('tapping a worktree row opens its path as a tab', (tester) async {
    await onDesktop(() async {
      final container = await _pump(tester, _trees);

      await tester.tap(find.text('feat/login'));
      await tester.pumpAndSettle();

      final paths = container.read(workspaceProvider).tabs.map((t) => t.path);
      expect(paths, contains('/home/u/repo-login'));
    });
  });

  testWidgets('shows the exact empty-state text when there are no worktrees', (
    tester,
  ) async {
    await onDesktop(() async {
      await _pump(tester, const []);

      expect(find.text('No worktrees'), findsOneWidget);
    });
  });

  testWidgets('remove from the row menu tries plain removal before forcing', (
    tester,
  ) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'feat/login');
      await tester.tap(find.text('Remove…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // The first attempt must never carry --force: that is the flag that
      // silently discards a user's uncommitted work. A successful mutation
      // also triggers a full repo-data reload (stash/refs/status/log/…),
      // so filter down to the `worktree remove` calls specifically rather
      // than asserting the full argv history.
      expect(_removeCalls(git), [
        ['worktree', 'remove', '/home/u/repo-login'],
      ]);
      expect(
        find.textContaining('contains modified or untracked files'),
        findsOneWidget,
      );

      await tester.tap(find.text('Force remove'));
      await tester.pumpAndSettle();

      expect(_removeCalls(git), [
        ['worktree', 'remove', '/home/u/repo-login'],
        ['worktree', 'remove', '--force', '/home/u/repo-login'],
      ]);
    });
  });

  testWidgets('locking with an empty reason locks without --reason', (
    tester,
  ) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'feat/login');
      await tester.tap(find.text('Lock…'));
      await tester.pumpAndSettle();
      // The field is labelled optional, so confirming it empty has to work.
      await tester.tap(find.text('Lock'));
      await tester.pumpAndSettle();

      expect(_worktreeCalls(git, 'lock'), [
        ['worktree', 'lock', '/home/u/repo-login'],
      ]);
    });
  });

  testWidgets('locking with a reason passes it through as --reason', (
    tester,
  ) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'feat/login');
      await tester.tap(find.text('Lock…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'on usb');
      await tester.tap(find.text('Lock'));
      await tester.pumpAndSettle();

      expect(_worktreeCalls(git, 'lock'), [
        ['worktree', 'lock', '--reason', 'on usb', '/home/u/repo-login'],
      ]);
    });
  });

  testWidgets('cancelling the lock dialog locks nothing', (tester) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'feat/login');
      await tester.tap(find.text('Lock…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'typed then thought '
        'better of it',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Cancel used to be the one way to reach a reasonless lock: the dialog
      // returned null and the null went straight to `git worktree lock`.
      expect(_worktreeCalls(git, 'lock'), isEmpty);
    });
  });

  testWidgets('unlock issues git worktree unlock for that path', (
    tester,
  ) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'locked-branch');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(_worktreeCalls(git, 'unlock'), [
        ['worktree', 'unlock', '/home/u/repo-locked'],
      ]);
    });
  });

  testWidgets('move issues git worktree move to the entered destination', (
    tester,
  ) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'feat/login');
      await tester.tap(find.text('Move…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('worktree-move-path')),
        '/home/u/repo-moved',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move'));
      await tester.pumpAndSettle();

      expect(_worktreeCalls(git, 'move'), [
        ['worktree', 'move', '/home/u/repo-login', '/home/u/repo-moved'],
      ]);
    });
  });

  testWidgets('cancelling the move dialog moves nothing', (tester) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'feat/login');
      await tester.tap(find.text('Move…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('worktree-move-path')),
        '/home/u/repo-moved',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(_worktreeCalls(git, 'move'), isEmpty);
    });
  });

  testWidgets('the move dialog refuses a destination inside the repository', (
    tester,
  ) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'feat/login');
      await tester.tap(find.text('Move…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('worktree-move-path')),
        '$_repoPath/inside',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Choose a location outside the repository'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Move'))
            .onPressed,
        isNull,
      );

      // The other worktree's location is taken, and standing still is not a
      // move — both are caught before git is asked.
      await tester.enterText(
        find.byKey(const Key('worktree-move-path')),
        '/home/u/repo-locked',
      );
      await tester.pumpAndSettle();
      expect(find.text('A worktree already lives there'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('worktree-move-path')),
        '/home/u/repo-login',
      );
      await tester.pumpAndSettle();
      expect(find.text('That is where it already is'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_worktreeCalls(git, 'move'), isEmpty);
    });
  });

  testWidgets('the section does not wear the Branches section icon', (
    tester,
  ) async {
    await onDesktop(() async {
      await _pump(tester, _trees);

      // call_split is the Branches section's glyph; two sections sharing one
      // icon read as the same thing.
      expect(find.byIcon(Icons.call_split), findsNothing);
      expect(find.byIcon(Icons.call_split_outlined), findsNothing);
      expect(find.byIcon(Icons.dashboard_outlined), findsWidgets);
    });
  });

  testWidgets('each row shows the directory the worktree lives in', (
    tester,
  ) async {
    await onDesktop(() async {
      await _pump(tester, _trees);

      for (final w in _trees) {
        expect(
          find.text(w.path),
          findsOneWidget,
          reason: 'two similarly named branches are told apart by their path',
        );
      }
    });
  });

  testWidgets('cancelling the force dialog never issues a forced removal', (
    tester,
  ) async {
    await onDesktop(() async {
      final git = _FakeGit();
      await _pumpWithGit(tester, _trees, git);

      await _openRowMenu(tester, 'feat/login');
      await tester.tap(find.text('Remove…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('contains modified or untracked files'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(_removeCalls(git), [
        ['worktree', 'remove', '/home/u/repo-login'],
      ]);
      expect(git.calls.any((c) => c.contains('--force')), isFalse);
    });
  });
}
