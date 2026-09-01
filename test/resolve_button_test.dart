import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _staged = WorkingFile(path: 'a.txt', index: GitChange.modified);

const _conflicted = WorkingFile(
  path: 'a.txt',
  index: GitChange.conflicted,
  worktree: GitChange.conflicted,
);

Widget _harness(RepoData data, {PendingOp? pending}) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
    pendingOpProvider('/r').overrideWith((ref) async => pending),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
  ],
  child: MaterialApp(
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(
      body: WorkingTreePanel(repoPath: '/r', data: data),
    ),
  ),
);

void main() {
  testWidgets('shows Resolve conflicts when a file is conflicted', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const RepoData(working: [_conflicted])));
    expect(find.text('Resolve conflicts'), findsOneWidget);
  });

  testWidgets('no Resolve conflicts button when nothing is conflicted', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const RepoData(
          working: [WorkingFile(path: 'b.txt', worktree: GitChange.modified)],
        ),
      ),
    );
    expect(find.text('Resolve conflicts'), findsNothing);
  });

  testWidgets('a paused rebase offers to continue it, not to commit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const RepoData(working: [_staged]),
        pending: const PendingOp(kind: MergeKind.rebase),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue rebase'), findsOneWidget);
    expect(find.text('Abort'), findsOneWidget);
    // Committing is not how a rebase finishes, so the button is held shut.
    final commit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Commit'),
    );
    expect(commit.onPressed, isNull);
  });

  testWidgets('an open merge is left to the commit composer', (tester) async {
    await tester.pumpWidget(
      _harness(
        const RepoData(working: [_staged]),
        pending: const PendingOp(kind: MergeKind.merge),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('A merge is open'), findsOneWidget);
    expect(find.text('Continue merge'), findsNothing);
    final commit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Commit'),
    );
    expect(commit.onPressed, isNotNull);
  });

  testWidgets('an open merge keeps the composer reachable on a clean tree', (
    tester,
  ) async {
    // Resolving every hunk to "ours" leaves nothing changed, but the merge
    // commit is still owed.
    await tester.pumpWidget(
      _harness(
        const RepoData(),
        pending: const PendingOp(kind: MergeKind.merge),
      ),
    );
    await tester.pumpAndSettle();

    final commit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Commit'),
    );
    expect(commit.onPressed, isNotNull);
  });

  testWidgets('no pending-operation bar when git is in the middle of nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const RepoData(working: [_staged])));
    await tester.pumpAndSettle();

    expect(find.text('Abort'), findsNothing);
    expect(find.textContaining('is paused'), findsNothing);
  });
}
