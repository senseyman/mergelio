// Files mode keeps several files open at once: a tab strip on top, one editor
// underneath, and a prompt before a tab with unsaved text is thrown away.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/files/file_editor_pane.dart';

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
        editableFileForPathProvider.overrideWith(
          (ref, FileRef key) async =>
              EditableFile(text: 'body of ${key.relPath}'),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: FileEditorPane(repoPath: '/r'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(FileEditorPane)));
}

Future<void> _open(
  WidgetTester tester,
  ProviderContainer c,
  List<String> paths,
) async {
  for (final p in paths) {
    c.read(openFilesProvider('/r').notifier).open(p);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with nothing open the pane invites opening a file', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Open a file to edit it'), findsOneWidget);
  });

  testWidgets('each open file gets a tab, the last one active', (tester) async {
    final c = await _pump(tester);

    await _open(tester, c, ['README.md', 'lib/main.dart']);

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('body of lib/main.dart'), findsOneWidget);
  });

  testWidgets('a tab carries its full path, since basenames collide', (
    tester,
  ) async {
    final c = await _pump(tester);

    await _open(tester, c, ['lib/main.dart']);

    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((w) => w.message)
          .toList(),
      contains('lib/main.dart'),
    );
  });

  testWidgets('clicking a tab brings its file back', (tester) async {
    final c = await _pump(tester);
    await _open(tester, c, ['README.md', 'lib/main.dart']);

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();

    expect(c.read(openFilesProvider('/r')).active, 'README.md');
    expect(find.text('body of README.md'), findsOneWidget);
    expect(find.text('body of lib/main.dart'), findsNothing);
  });

  testWidgets('a clean tab closes without asking', (tester) async {
    final c = await _pump(tester);
    await _open(tester, c, ['README.md', 'lib/main.dart']);

    await tester.tap(find.byTooltip('Close lib/main.dart'));
    await tester.pumpAndSettle();

    expect(c.read(openFilesProvider('/r')).paths, ['README.md']);
    expect(find.text('body of README.md'), findsOneWidget);
  });

  testWidgets('editing marks the tab unsaved', (tester) async {
    final c = await _pump(tester);
    await _open(tester, c, ['README.md']);

    await tester.enterText(find.byType(TextField), 'changed');
    await tester.pumpAndSettle();

    expect(c.read(openFilesProvider('/r')).dirty, {'README.md'});
    expect(find.byKey(const ValueKey('unsaved:README.md')), findsOneWidget);
  });

  testWidgets('closing an unsaved tab asks first, and cancel keeps it', (
    tester,
  ) async {
    final c = await _pump(tester);
    await _open(tester, c, ['README.md']);
    await tester.enterText(find.byType(TextField), 'changed');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close README.md'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(c.read(openFilesProvider('/r')).paths, ['README.md']);
  });

  testWidgets('discarding closes the unsaved tab', (tester) async {
    final c = await _pump(tester);
    await _open(tester, c, ['README.md']);
    await tester.enterText(find.byType(TextField), 'changed');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close README.md'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(c.read(openFilesProvider('/r')).paths, isEmpty);
  });

  testWidgets('a file deleted underneath its tab says so', (tester) async {
    final c = await _pump(tester);
    await _open(tester, c, ['README.md']);

    c.read(openFilesProvider('/r').notifier).markGone('README.md');
    await tester.pumpAndSettle();

    expect(find.text('Deleted on disk — saving is disabled'), findsOneWidget);
  });
}
