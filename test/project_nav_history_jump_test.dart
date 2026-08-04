// "Show history" on a navigator row hands the path to the graph: the tab goes
// back to history with the search filtered to that file.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/search.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/files/project_nav_panel.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _tree = {
  '': DirListing(entries: [DirEntry(name: 'README.md', isDir: false)]),
};

void main() {
  testWidgets('showing the history of a file filters the graph by it', (
    tester,
  ) async {
    final workspace = WorkspaceController()..openRepo('/r');
    workspace.setViewMode(workspace.state.activeTab!.id, RepoViewMode.files);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          workspaceProvider.overrideWith((ref) => workspace),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          dirListingProvider.overrideWith(
            (ref, DirKey key) async =>
                _tree[key.relDir] ?? const DirListing(error: 'missing'),
          ),
          ignoredInDirProvider.overrideWith(
            (ref, DirKey key) async => const {},
          ),
          trackedPathsProvider.overrideWith(
            (ref, String repo) async => const {'README.md'},
          ),
          repoDataProvider.overrideWith(
            (ref, String repo) async => const RepoData(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: ProjectNavPanel(repoPath: '/r'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('README.md')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show history'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProjectNavPanel)),
    );
    expect(container.read(searchQueryProvider)?.path, 'README.md');
    expect(workspace.state.activeTab!.viewMode, RepoViewMode.graph);
  });
}
