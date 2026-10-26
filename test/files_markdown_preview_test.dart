// A Markdown tab in Files mode can be flipped between its source and a
// rendered view and back. The rendered view shows what the editor holds,
// saved or not, and each tab remembers its own choice. Filesystem-reading
// providers are faked — they never resolve under testWidgets.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/common/file_text_editor.dart';
import 'package:mergelio/ui/common/markdown_view.dart';
import 'package:mergelio/ui/files/files_view.dart';

const _files = {
  'README.md': '# Hello\n\nSee [the guide](docs/guide.md).\n',
  'docs/guide.md': '# Guide\n',
  'notes.md': '# Notes\n',
  'main.dart': 'void main() {}\n',
};

Future<ProviderContainer> _pump(WidgetTester tester, List<String> open) async {
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
          (ref, DirKey key) async => const DirListing(entries: []),
        ),
        editableFileForPathProvider.overrideWith(
          (ref, FileRef key) async => EditableFile(text: _files[key.relPath]!),
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
  final container = ProviderScope.containerOf(
    tester.element(find.byType(FilesView)),
  );
  final files = container.read(openFilesProvider('/r').notifier);
  open.forEach(files.open);
  await tester.pumpAndSettle();
  return container;
}

final _source = find.byKey(const ValueKey('md:source'));
final _rendered = find.byKey(const ValueKey('md:rendered'));
final _field = find.byKey(const ValueKey('editor:body'));

/// The field even while the rendered view hides it.
final _anyField = find.byKey(
  const ValueKey('editor:body'),
  skipOffstage: false,
);

void main() {
  testWidgets('a Markdown tab opens on its source', (tester) async {
    await _pump(tester, ['README.md']);

    expect(_source, findsOneWidget);
    expect(_rendered, findsOneWidget);
    expect(find.byType(MarkdownView), findsNothing);
    expect(_field.hitTestable(), findsOneWidget);
  });

  testWidgets('any other file offers no rendered view', (tester) async {
    await _pump(tester, ['main.dart']);

    expect(_source, findsNothing);
    expect(_rendered, findsNothing);
  });

  testWidgets('Preview renders the file, Source brings the field back', (
    tester,
  ) async {
    await _pump(tester, ['README.md']);
    await tester.tap(_field);
    await tester.pump();
    expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);

    await tester.tap(_rendered);
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(_field.hitTestable(), findsNothing);
    // Keys must not reach a field nobody can see.
    expect(tester.widget<TextField>(_anyField).focusNode!.hasFocus, isFalse);
    // But they must still reach the editor, for save and its other keys,
    // rather than falling back to the navigator.
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(focused.findAncestorWidgetOfExactType<FileTextEditor>(), isNotNull);

    await tester.tap(_source);
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownView), findsNothing);
    expect(_field.hitTestable(), findsOneWidget);
  });

  testWidgets('unsaved text is what gets rendered, and it survives the trip', (
    tester,
  ) async {
    final container = await _pump(tester, ['README.md']);

    await tester.enterText(_field, '# Typed heading\n');
    await tester.pump();
    final ctl = tester.widget<TextField>(_field).controller!;
    ctl.selection = const TextSelection.collapsed(offset: 4);

    await tester.tap(_rendered);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Typed heading', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Hello', findRichText: true), findsNothing);
    // Still unsaved while it is shown rendered.
    expect(
      container.read(openFilesProvider('/r')).isDirty('README.md'),
      isTrue,
    );

    await tester.tap(_source);
    await tester.pumpAndSettle();
    final back = tester.widget<TextField>(_field).controller!;
    expect(back.text, '# Typed heading\n');
    expect(back.selection, const TextSelection.collapsed(offset: 4));
  });

  testWidgets('back on the source, typing goes into the field again', (
    tester,
  ) async {
    await _pump(tester, ['README.md']);

    await tester.tap(_rendered);
    await tester.pumpAndSettle();
    await tester.tap(_source);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(_field);
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('each tab keeps its own view', (tester) async {
    final container = await _pump(tester, ['README.md', 'notes.md']);
    final files = container.read(openFilesProvider('/r').notifier);

    files.activate('README.md');
    await tester.pumpAndSettle();
    await tester.tap(_rendered);
    await tester.pumpAndSettle();

    files.activate('notes.md');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Offstage).hitTestable(),
        matching: find.byType(MarkdownView),
      ),
      findsNothing,
    );
    expect(
      container.read(openFilesProvider('/r')).isRendered('notes.md'),
      isFalse,
    );

    files.activate('README.md');
    await tester.pumpAndSettle();
    expect(
      container.read(openFilesProvider('/r')).isRendered('README.md'),
      isTrue,
    );
    expect(
      find.textContaining('Hello', findRichText: true).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('a link to another repository file opens it in a tab', (
    tester,
  ) async {
    final container = await _pump(tester, ['README.md']);

    await tester.tap(_rendered);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('the guide', findRichText: true));
    await tester.pumpAndSettle();

    final open = container.read(openFilesProvider('/r'));
    expect(open.paths, ['README.md', 'docs/guide.md']);
    expect(open.active, 'docs/guide.md');
  });

  testWidgets('undo and redo cannot change the text behind the rendered view', (
    tester,
  ) async {
    await _pump(tester, ['README.md']);
    await tester.tap(_field);
    // Undo history ignores a field that has only just taken focus.
    await tester.pump(const Duration(milliseconds: 600));
    // Typed through the input channel so the edit lands in undo history, and
    // on the same number of lines so nothing else forces a rebuild.
    const typed = '# Hello!\n\nSee [the guide](docs/guide.md).\n';
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: 8),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    String text() => tester.widget<TextField>(_anyField).controller!.text;
    Future<void> press({bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
    }

    Future<void> view(Finder toggle) async {
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    // Undo is held off while previewing, so what is shown is what is held.
    await view(_rendered);
    await press();
    expect(text(), typed);
    expect(find.textContaining('Hello!', findRichText: true), findsOneWidget);

    // On the source it works as before.
    await view(_source);
    await press();
    expect(text(), _files['README.md']);

    // Redo is held off the same way.
    await view(_rendered);
    await press(shift: true);
    expect(text(), _files['README.md']);

    await view(_source);
    await press(shift: true);
    expect(text(), typed);
  });

  testWidgets('find open on the source is closed by switching to Preview', (
    tester,
  ) async {
    await _pump(tester, ['README.md']);
    await tester.tap(_field);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find:query')), findsOneWidget);

    await tester.tap(_rendered);
    await tester.pumpAndSettle();
    await tester.tap(_source);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('find:query')), findsNothing);
  });

  testWidgets('a tab renamed away from Markdown shows its source', (
    tester,
  ) async {
    final container = await _pump(tester, ['README.md']);
    await tester.tap(_rendered);
    await tester.pumpAndSettle();

    container
        .read(openFilesProvider('/r').notifier)
        .rename('README.md', 'main.dart');
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownView), findsNothing);
    expect(_field.hitTestable(), findsOneWidget);
  });

  testWidgets('find stays closed while the file is rendered', (tester) async {
    await _pump(tester, ['README.md']);

    await tester.tap(_rendered);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('find:query')), findsNothing);
    expect(find.byType(FileTextEditor), findsOneWidget);

    // Nor does it pop up once the source is back.
    await tester.tap(_source);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find:query')), findsNothing);
  });
}
