import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

class _FakeGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(a);
    if (a.first == 'config') return const GitResult(0, 'diff.tool\nx\x00', '');
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// A working-tree row hands its file to the editor and, when there is a
/// change to compare, to git's diff tool — on the side of the list it sits in.
void main() {
  Future<_FakeGit> pump(WidgetTester tester, List<WorkingFile> files) async {
    final git = _FakeGit();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
          gitServiceProvider.overrideWithValue(git),
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
          home: Scaffold(
            body: WorkingTreePanel(
              repoPath: '/r',
              data: RepoData(working: files),
            ),
          ),
        ),
      ),
    );
    return git;
  }

  testWidgets('a staged change opens the staged side in the diff tool', (
    tester,
  ) async {
    final git = await pump(tester, const [
      WorkingFile(path: 'a.txt', index: GitChange.modified),
    ]);
    await tester.tap(find.text('a.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Open in editor'), findsOneWidget);
    await tester.tap(find.text('Open in diff tool'));
    await tester.pumpAndSettle();
    expect(git.calls.where((c) => c.first == 'difftool').single, [
      'difftool',
      '--no-prompt',
      '--cached',
      '--',
      'a.txt',
    ]);
  });

  testWidgets('an untracked file has nothing for a diff tool', (tester) async {
    await pump(tester, const [
      WorkingFile(path: 'new.txt', worktree: GitChange.untracked),
    ]);
    await tester.tap(find.text('new.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Open in editor'), findsOneWidget);
    expect(find.text('Open in diff tool'), findsNothing);
  });
}
