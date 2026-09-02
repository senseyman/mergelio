// Right-clicking the empty space of the navigator. There is no row there, so
// the menu is about the project root: it creates, and it offers nothing that
// would need something to have been picked.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/project_ops.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/project_ops_provider.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/files/project_nav_panel.dart';

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

/// Records filesystem operations; the navigator never sees a real disk here.
class _RecordingOps extends ProjectOps {
  _RecordingOps(super.repoPath);

  final created = <String>[];

  @override
  Future<ProjectOpResult> createFile(String relDir, String name) async {
    created.add('$relDir|$name');
    return ProjectOpResult.done(relDir.isEmpty ? name : '$relDir/$name');
  }

  @override
  Future<ProjectOpResult> createFolder(String relDir, String name) async {
    created.add('$relDir|$name');
    return ProjectOpResult.done(relDir.isEmpty ? name : '$relDir/$name');
  }
}

/// One short row, so most of the panel is empty space to click in.
const _tree = {
  '': DirListing(entries: [DirEntry(name: 'README.md', isDir: false)]),
};

void main() {
  late _RecordingOps ops;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
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
          projectOpsProvider.overrideWith(
            (ref, path) => ops = _RecordingOps(path),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProjectNavPanel)),
    );
    container.read(projectOpsProvider('/r'));
    return container;
  }

  /// Well below the single row, in the panel's empty area.
  Future<void> rightClickEmpty(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ProjectNavPanel)) + const Offset(0, 200),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the empty area offers creating in the project root', (
    tester,
  ) async {
    await pump(tester);

    await rightClickEmpty(tester);

    expect(find.text('New file…'), findsOneWidget);
    expect(find.text('New folder…'), findsOneWidget);
    // Nothing was picked, so there is nothing to rename, delete or stage.
    expect(find.text('Rename…'), findsNothing);
    expect(find.text('Delete…'), findsNothing);
  });

  testWidgets('a file made there is made in the root, not inside a row', (
    tester,
  ) async {
    await pump(tester);

    await rightClickEmpty(tester);
    await tester.tap(find.text('New file…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'notes.md');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(ops.created, ['|notes.md']);
  });

  testWidgets('a folder made there is made in the root too', (tester) async {
    await pump(tester);

    await rightClickEmpty(tester);
    await tester.tap(find.text('New folder…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'docs');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(ops.created, ['|docs']);
  });

  testWidgets('right-clicking a row still gets the row menu', (tester) async {
    await pump(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('README.md')),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Rename…'), findsOneWidget);
    // The root menu must not have opened underneath it.
    expect(find.text('New file…'), findsNothing);
  });

  testWidgets('the new file is opened for editing', (tester) async {
    final c = await pump(tester);

    await rightClickEmpty(tester);
    await tester.tap(find.text('New file…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'notes.md');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(c.read(openFilesProvider('/r')).active, 'notes.md');
  });
}
