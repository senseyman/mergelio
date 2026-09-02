// Files mode pairs the navigator with an editor: what the navigator selects is
// what the right-hand pane opens. Filesystem-reading providers are faked —
// they never resolve under testWidgets.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/common/file_text_editor.dart';
import 'package:mergelio/ui/files/files_view.dart';

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
        editableFileForPathProvider.overrideWith(
          (ref, FileRef key) async =>
              EditableFile(text: '// ${key.relPath}\nvoid main() {}\n'),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: FilesView(repoPath: '/r'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(FilesView)));
}

void main() {
  testWidgets('with nothing selected the pane invites opening a file', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byType(FileTextEditor), findsNothing);
    expect(find.text('Open a file to edit it'), findsOneWidget);
  });

  testWidgets('selecting a file opens it in the editor', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();

    expect(find.byType(FileTextEditor), findsOneWidget);
    expect(find.text('// README.md\nvoid main() {}\n'), findsOneWidget);
  });

  testWidgets('the open file gets a tab above the editor', (tester) async {
    final container = await _pump(tester);
    container.read(openFilesProvider('/r').notifier).open('lib/main.dart');
    await tester.pumpAndSettle();

    // The tree shows the folder, the tab shows the file it holds.
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('switching files replaces what the editor holds', (tester) async {
    final container = await _pump(tester);
    container.read(openFilesProvider('/r').notifier).open('README.md');
    await tester.pumpAndSettle();

    container.read(openFilesProvider('/r').notifier).open('lib/main.dart');
    await tester.pumpAndSettle();

    expect(find.text('// lib/main.dart\nvoid main() {}\n'), findsOneWidget);
    expect(find.text('// README.md\nvoid main() {}\n'), findsNothing);
  });
}
