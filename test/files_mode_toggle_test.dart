// Files mode is entered from the toolbar and is remembered per repo tab, so
// switching repos restores whichever view that repo was left in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/files/files_view.dart';
import 'package:mergelio/ui/shell/app_toolbar.dart';
import 'package:mergelio/ui/workspace/workspace_view.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
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

Widget _wrap(Widget child, WorkspaceController workspace) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
    workspaceProvider.overrideWith((ref) => workspace),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('the toolbar button switches the active tab into files mode', (
    tester,
  ) async {
    final workspace = WorkspaceController()..openRepo('/r');
    await tester.pumpWidget(_wrap(const AppToolbar(), workspace));

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pump();

    expect(workspace.state.activeTab!.viewMode, RepoViewMode.files);

    // The same button goes back, now showing the history icon.
    await tester.tap(find.byIcon(Icons.history));
    await tester.pump();
    expect(workspace.state.activeTab!.viewMode, RepoViewMode.graph);
  });

  testWidgets('the toolbar button is disabled with no repo open', (
    tester,
  ) async {
    final workspace = WorkspaceController();
    await tester.pumpWidget(_wrap(const AppToolbar(), workspace));

    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pump();
    expect(workspace.state.activeTab, isNull);
  });

  testWidgets('the workspace shows FilesView when the tab is in files mode', (
    tester,
  ) async {
    final workspace = WorkspaceController();
    final tab = workspace.openRepo('/r');
    workspace.setViewMode(tab.id, RepoViewMode.files);

    await tester.pumpWidget(_wrap(const WorkspaceView(), workspace));
    await tester.pump();

    expect(find.byType(FilesView), findsOneWidget);
  });
}
