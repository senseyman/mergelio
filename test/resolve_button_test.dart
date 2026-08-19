import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/data/settings_repository.dart';
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

const _conflicted = WorkingFile(
  path: 'a.txt',
  index: GitChange.conflicted,
  worktree: GitChange.conflicted,
);

Widget _harness(RepoData data) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
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
}
