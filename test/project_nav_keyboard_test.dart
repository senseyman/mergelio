// The navigator is usable from the keyboard: arrows move and open folders,
// Enter opens the focused file.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/files/project_nav_panel.dart';

/// root: lib/ then README.md; lib/ holds main.dart.
const _tree = {
  '': DirListing(
    entries: [
      DirEntry(name: 'lib', isDir: true),
      DirEntry(name: 'README.md', isDir: false),
    ],
  ),
  'lib': DirListing(entries: [DirEntry(name: 'main.dart', isDir: false)]),
};

Future<ProviderContainer> _pump(WidgetTester tester) async {
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
        trackedPathsProvider.overrideWith((ref, String _) async => const {}),
        ignoredInDirProvider.overrideWith((ref, DirKey _) async => const {}),
      ],
      child: MaterialApp(
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

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('down moves the cursor onto the first row', (tester) async {
    final c = await _pump(tester);

    await _key(tester, LogicalKeyboardKey.arrowDown);

    expect(c.read(navCursorProvider('/r')), 'lib');
  });

  testWidgets('down again moves past a closed folder to the next row', (
    tester,
  ) async {
    final c = await _pump(tester);

    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);

    expect(c.read(navCursorProvider('/r')), 'README.md');
  });

  testWidgets('up moves back and stops at the top', (tester) async {
    final c = await _pump(tester);

    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    await _key(tester, LogicalKeyboardKey.arrowUp);

    expect(c.read(navCursorProvider('/r')), 'lib');
  });

  testWidgets('right expands the folder under the cursor', (tester) async {
    final c = await _pump(tester);

    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowRight);

    expect(c.read(expandedDirsProvider('/r')), contains('lib'));
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('left collapses the expanded folder again', (tester) async {
    final c = await _pump(tester);

    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.arrowLeft);

    expect(c.read(expandedDirsProvider('/r')), isEmpty);
  });

  testWidgets('enter opens the file under the cursor', (tester) async {
    final c = await _pump(tester);

    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.enter);

    expect(c.read(openFilesProvider('/r')).active, 'README.md');
  });

  testWidgets('clicking a row moves the cursor there', (tester) async {
    // Keyboard and mouse drive one cursor, so arrows continue from the click.
    final c = await _pump(tester);

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.arrowUp);

    expect(c.read(navCursorProvider('/r')), 'lib');
  });
}
