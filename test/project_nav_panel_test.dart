// The navigator lists one directory at a time; expanding a folder is what
// triggers reading it. Listings are faked here — a filesystem-reading provider
// never resolves under testWidgets.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/files/project_nav_panel.dart';

/// Fake tree: root has lib/ and README.md; lib/ has main.dart.
const _tree = {
  '': DirListing(
    entries: [
      DirEntry(name: 'lib', isDir: true),
      DirEntry(name: 'README.md', isDir: false),
    ],
  ),
  'lib': DirListing(entries: [DirEntry(name: 'main.dart', isDir: false)]),
};

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, DirListing> tree = _tree,
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
              tree[key.relDir] ?? const DirListing(error: 'missing'),
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

void main() {
  testWidgets('the root listing renders, with folders before files', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('lib'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    // Nothing inside lib/ until it is opened.
    expect(find.text('main.dart'), findsNothing);
  });

  testWidgets('tapping a folder expands it and shows its children', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    expect(container.read(expandedDirsProvider('/r')), contains('lib'));
    expect(find.text('main.dart'), findsOneWidget);

    // Tapping again collapses it.
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsNothing);
  });

  testWidgets('tapping a file selects it', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();

    expect(container.read(openFilesProvider('/r')).active, 'README.md');
  });

  testWidgets('a nested file selects by its full repo-relative path', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();

    expect(container.read(openFilesProvider('/r')).active, 'lib/main.dart');
  });

  testWidgets('an unreadable directory shows its error in place of children', (
    tester,
  ) async {
    await _pump(
      tester,
      tree: const {
        '': DirListing(entries: [DirEntry(name: 'secret', isDir: true)]),
        'secret': DirListing(error: 'Permission denied'),
      },
    );

    await tester.tap(find.text('secret'));
    await tester.pumpAndSettle();

    expect(find.text('Permission denied'), findsOneWidget);
  });
}
