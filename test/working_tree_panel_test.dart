import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

class _FakeGit implements GitService {
  final calls = <List<String>>[];
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _staged = WorkingFile(path: 'staged.txt', index: GitChange.modified);
const _unstaged = WorkingFile(path: 'unstaged.txt', worktree: GitChange.added);
const _partial = WorkingFile(
  path: 'partial.txt',
  index: GitChange.modified,
  worktree: GitChange.modified,
);

Widget _harness(_FakeGit git, RepoData data) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(git),
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
  testWidgets('clean tree shows the empty state, no composer', (tester) async {
    await tester.pumpWidget(_harness(_FakeGit(), const RepoData()));
    expect(find.text('Working tree clean'), findsOneWidget);
    expect(find.text('Commit'), findsNothing);
  });

  testWidgets('lists staged and unstaged; a partial file shows in both', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _FakeGit(),
        const RepoData(working: [_staged, _unstaged, _partial]),
      ),
    );
    expect(find.text('STAGED (2)'), findsOneWidget); // staged + partial
    expect(find.text('UNSTAGED (2)'), findsOneWidget); // unstaged + partial
    expect(find.text('partial'), findsNWidgets(2));
  });

  testWidgets('tapping a file opens it in the diff target', (tester) async {
    await tester.pumpWidget(
      _harness(_FakeGit(), const RepoData(working: [_unstaged])),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    );
    await tester.tap(find.text('unstaged.txt'));
    await tester.pump();
    expect(container.read(diffTargetProvider)?.path, 'unstaged.txt');
  });

  testWidgets('empty summary is blocked with a warning, no git commit', (
    tester,
  ) async {
    final git = _FakeGit();
    await tester.pumpWidget(_harness(git, const RepoData(working: [_staged])));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Commit'));
    await tester.pump();

    expect(git.calls.any((c) => c.first == 'commit'), isFalse);
    expect(
      container.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
  });

  testWidgets('a summary with staged changes runs git commit', (tester) async {
    final git = _FakeGit();
    await tester.pumpWidget(_harness(git, const RepoData(working: [_staged])));
    await tester.enterText(find.byType(TextField).first, 'my message');
    await tester.tap(find.widgetWithText(FilledButton, 'Commit'));
    await tester.pump();

    final commitCall = git.calls.firstWhere((c) => c.first == 'commit');
    expect(commitCall, contains('my message'));
  });
}
