import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
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

/// Records the discard instead of touching a repository.
class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  final calls = <bool>[];

  @override
  Future<void> discardAll({bool includeUntracked = false}) async {
    calls.add(includeUntracked);
  }
}

const _dirty = RepoData(
  working: [
    WorkingFile(path: 'a.txt', worktree: GitChange.modified),
    WorkingFile(path: 'b.txt', worktree: GitChange.untracked),
    WorkingFile(path: 'c.txt', worktree: GitChange.untracked),
  ],
);

void main() {
  late _RecordingActions actions;

  Widget harness(RepoData data) => ProviderScope(
    overrides: [
      gitServiceProvider.overrideWithValue(_FakeGit()),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
      repoActionsProvider.overrideWith(
        (ref, path) =>
            actions = _RecordingActions(ref, path, GitWriter(_FakeGit(), path)),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [AppTokens.dark()]),
      home: Scaffold(
        body: WorkingTreePanel(repoPath: '/r', data: data),
      ),
    ),
  );

  // The file rows carry staging checkboxes of their own, so the prompt's has
  // to be looked for inside the dialog.
  final promptCheckbox = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(Checkbox),
  );

  Future<void> openPrompt(WidgetTester tester) async {
    await tester.pumpWidget(harness(_dirty));
    await tester.tap(find.byTooltip('Discard all changes'));
    await tester.pumpAndSettle();
  }

  testWidgets('the action is hidden while the tree is clean', (tester) async {
    await tester.pumpWidget(harness(const RepoData()));
    expect(find.byTooltip('Discard all changes'), findsNothing);
  });

  testWidgets('discarding leaves untracked files alone by default', (
    tester,
  ) async {
    await openPrompt(tester);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(actions.calls, [false]);
  });

  testWidgets('the untracked checkbox names how many files it deletes', (
    tester,
  ) async {
    await openPrompt(tester);

    expect(find.text('Also delete 2 untracked files'), findsOneWidget);

    await tester.tap(promptCheckbox);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(actions.calls, [true]);
  });

  testWidgets('no untracked files means no checkbox', (tester) async {
    await tester.pumpWidget(
      harness(
        const RepoData(
          working: [WorkingFile(path: 'a.txt', worktree: GitChange.modified)],
        ),
      ),
    );
    await tester.tap(find.byTooltip('Discard all changes'));
    await tester.pumpAndSettle();

    expect(promptCheckbox, findsNothing);
  });

  testWidgets('cancelling discards nothing', (tester) async {
    await openPrompt(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(actions.calls, isEmpty);
  });
}
