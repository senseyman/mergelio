// The navigator paints what git says: badges for changed and untracked files,
// dimming for ignored ones, and a toggle that takes ignored rows away.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/files/project_nav_panel.dart';

const _tree = {
  '': DirListing(
    entries: [
      DirEntry(name: 'build', isDir: true),
      DirEntry(name: 'lib', isDir: true),
      DirEntry(name: 'README.md', isDir: false),
      DirEntry(name: 'scratch.txt', isDir: false),
      DirEntry(name: 'notes.log', isDir: false),
    ],
  ),
};

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Set<String>? tracked = const {'README.md'},
  Set<String> ignored = const {'notes.log', 'build'},
  List<WorkingFile> working = const [
    WorkingFile(path: 'README.md', worktree: GitChange.modified),
  ],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        trackedPathsProvider.overrideWith((ref, String _) async => tracked),
        ignoredInDirProvider.overrideWith((ref, DirKey _) async => ignored),
        repoDataProvider.overrideWith(
          (ref, String _) async => RepoData(working: working),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: ProjectNavPanel(repoPath: '/r'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(ProjectNavPanel)),
  );
}

Color _rowColor(WidgetTester tester, String name) =>
    tester.widget<Text>(find.text(name)).style!.color!;

void main() {
  testWidgets('a modified file carries an M badge', (tester) async {
    await _pump(tester);

    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('an untracked file carries a U badge', (tester) async {
    await _pump(tester);

    // scratch.txt is on disk, not tracked and not ignored.
    expect(find.text('U'), findsOneWidget);
  });

  testWidgets('an ignored row is dimmed and unbadged', (tester) async {
    await _pump(tester);

    expect(find.text('notes.log'), findsOneWidget);
    expect(
      _rowColor(tester, 'notes.log'),
      isNot(_rowColor(tester, 'scratch.txt')),
    );
  });

  testWidgets('hiding ignored files takes those rows away', (tester) async {
    final container = await _pump(tester);
    expect(find.text('notes.log'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide ignored files'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).filesHideIgnored, isTrue);
    expect(find.text('notes.log'), findsNothing);
    expect(find.text('build'), findsNothing);
    expect(find.text('scratch.txt'), findsOneWidget);
  });

  testWidgets('a failed tracking read leaves every row unbadged', (
    tester,
  ) async {
    await _pump(tester, tracked: null, ignored: const {}, working: const []);

    expect(find.text('M'), findsNothing);
    expect(find.text('U'), findsNothing);
  });
}
