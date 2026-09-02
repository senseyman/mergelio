import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/workspace/branch_tree.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';
import 'package:mergelio/ui/workspace/sidebar_section.dart';

Branch _b(String name, {bool current = false}) =>
    Branch(name: name, current: current);

void main() {
  group('buildBranchTree', () {
    test('flat branches become sorted leaf rows at depth 0', () {
      final rows = buildBranchTree([_b('main'), _b('dev')], const {});
      expect(rows.length, 2);
      expect(rows.every((r) => r is BranchLeafRow && r.depth == 0), isTrue);
      expect((rows[0] as BranchLeafRow).branch.name, 'dev');
      expect((rows[1] as BranchLeafRow).branch.name, 'main');
    });

    test('a `/` name creates a folder with its branches nested one level', () {
      final rows = buildBranchTree([
        _b('feature/a'),
        _b('feature/b'),
      ], const {});
      expect(rows.length, 3);

      final folder = rows[0] as BranchFolderRow;
      expect(folder.name, 'feature');
      expect(folder.id, 'branchdir:feature');
      expect(folder.open, isTrue);
      expect(folder.depth, 0);

      expect((rows[1] as BranchLeafRow).branch.name, 'feature/a');
      expect(rows[1].depth, 1);
      expect((rows[2] as BranchLeafRow).branch.name, 'feature/b');
    });

    test('a collapsed folder hides its descendants', () {
      final rows = buildBranchTree(
        [_b('feature/a'), _b('feature/b')],
        const {'branchdir:feature': true},
      );
      expect(rows.length, 1);
      final folder = rows[0] as BranchFolderRow;
      expect(folder.open, isFalse);
    });

    test('nested folders carry a path-prefixed id and increasing depth', () {
      final rows = buildBranchTree([_b('a/b/c')], const {});
      expect(rows.length, 3);
      expect((rows[0] as BranchFolderRow).id, 'branchdir:a');
      expect(rows[0].depth, 0);
      expect((rows[1] as BranchFolderRow).id, 'branchdir:a/b');
      expect(rows[1].depth, 1);
      expect((rows[2] as BranchLeafRow).branch.name, 'a/b/c');
      expect(rows[2].depth, 2);
    });

    test('folders sort before leaves at each level, each group sorted', () {
      final rows = buildBranchTree([
        _b('zzz'),
        _b('feature/x'),
        _b('aaa'),
      ], const {});
      expect(rows.length, 4);
      expect((rows[0] as BranchFolderRow).name, 'feature');
      expect((rows[1] as BranchLeafRow).branch.name, 'feature/x');
      expect(rows[1].depth, 1);
      expect((rows[2] as BranchLeafRow).branch.name, 'aaa');
      expect(rows[2].depth, 0);
      expect((rows[3] as BranchLeafRow).branch.name, 'zzz');
    });
  });

  group('the sidebar badges branches held by another worktree', () {
    const repoPath = '/r';

    Future<void> pump(
      WidgetTester tester, {
      required Map<String, Worktree> heldBy,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repoDataProvider(repoPath).overrideWith(
              (ref) async =>
                  const RepoData(branches: [Branch(name: 'feat/login')]),
            ),
            worktreeByBranchProvider(repoPath).overrideWithValue(heldBy),
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
            home: Scaffold(body: RepoSidebar(onCollapse: () {})),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RepoSidebar)),
      );
      container.read(workspaceProvider.notifier).openRepo(repoPath);
      await tester.pumpAndSettle();
    }

    /// The badge, the tab marker and the Worktrees section header all use one
    /// glyph to mean "worktree", so this looks inside the Branches section
    /// rather than across the whole sidebar.
    Finder badge() => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is SidebarSection && w.id == 'branches',
      ),
      matching: find.byIcon(Icons.dashboard_outlined),
    );

    testWidgets('a branch held by another worktree carries a badge', (
      tester,
    ) async {
      await pump(
        tester,
        heldBy: {
          'feat/login': const Worktree(
            path: '/home/u/repo-login',
            branch: 'feat/login',
          ),
        },
      );
      expect(badge(), findsOneWidget);
    });

    testWidgets('a branch held by the current worktree carries no badge', (
      tester,
    ) async {
      await pump(
        tester,
        heldBy: {
          'feat/login': const Worktree(path: repoPath, branch: 'feat/login'),
        },
      );
      expect(badge(), findsNothing);
    });
  });
}
