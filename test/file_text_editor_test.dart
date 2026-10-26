// One editing widget backs both the diff sheet and Files mode, so the guards,
// the dirty tracking and the save path cannot drift apart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/ui/common/file_text_editor.dart';

void main() {
  Future<List<bool>> pump(
    WidgetTester tester,
    EditableFile file, {
    Future<bool> Function(String path, String text)? onSave,
    EditorDraft? draft,
    ValueChanged<EditorDraft?>? onDraftChanged,
  }) async {
    final dirty = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editableFileForPathProvider.overrideWith(
            (ref, FileRef _) async => file,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: FileTextEditor(
              repoPath: '/r',
              relPath: 'lib/main.dart',
              onDirtyChanged: dirty.add,
              onSave: onSave,
              draft: draft,
              onDraftChanged: onDraftChanged,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return dirty;
  }

  testWidgets('the file text is seeded into the field', (tester) async {
    await pump(tester, const EditableFile(text: 'void main() {}'));
    expect(find.text('void main() {}'), findsOneWidget);
  });

  testWidgets('typing reports dirty, and reverting reports clean again', (
    tester,
  ) async {
    final dirty = await pump(tester, const EditableFile(text: 'abc'));

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();
    expect(dirty.last, isTrue);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(dirty.last, isFalse);
  });

  testWidgets('a blocked file shows the reason instead of an editor', (
    tester,
  ) async {
    await pump(
      tester,
      const EditableFile(blocker: 'Binary file — cannot be edited here'),
    );

    expect(find.text('Binary file — cannot be edited here'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Ctrl+S saves the typed text', (tester) async {
    String? savedPath;
    String? savedText;
    await pump(
      tester,
      const EditableFile(text: 'abc'),
      onSave: (path, text) async {
        savedPath = path;
        savedText = text;
        return true;
      },
    );

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(savedPath, 'lib/main.dart');
    expect(savedText, 'abcd');
  });

  testWidgets('a successful save reports the editor clean', (tester) async {
    final dirty = await pump(
      tester,
      const EditableFile(text: 'abc'),
      onSave: (path, text) async => true,
    );

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();
    expect(dirty.last, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(dirty.last, isFalse);
  });

  testWidgets('a refused save leaves the editor dirty and holding the text', (
    tester,
  ) async {
    final dirty = await pump(
      tester,
      const EditableFile(text: 'abc'),
      onSave: (path, text) async => false,
    );

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(dirty.last, isTrue);
    expect(find.text('abcd'), findsOneWidget);
  });

  group('drafts', () {
    testWidgets('typing reports the unsaved text with its baseline', (
      tester,
    ) async {
      final drafts = <EditorDraft?>[];
      await pump(
        tester,
        const EditableFile(text: 'abc'),
        onDraftChanged: drafts.add,
      );

      await tester.enterText(find.byType(TextField), 'abcd');
      await tester.pump();

      expect(drafts.last?.text, 'abcd');
      expect(drafts.last?.baseline.text, 'abc');
    });

    testWidgets('reverting to what is on disk reports no draft', (
      tester,
    ) async {
      final drafts = <EditorDraft?>[];
      await pump(
        tester,
        const EditableFile(text: 'abc'),
        onDraftChanged: drafts.add,
      );

      await tester.enterText(find.byType(TextField), 'abcd');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      expect(drafts.last, isNull);
    });

    testWidgets('a saved editor reports no draft', (tester) async {
      final drafts = <EditorDraft?>[];
      await pump(
        tester,
        const EditableFile(text: 'abc'),
        onSave: (path, text) async => true,
        onDraftChanged: drafts.add,
      );

      await tester.enterText(find.byType(TextField), 'abcd');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(drafts.last, isNull);
    });

    testWidgets('a draft is seeded in place of the file and reads dirty', (
      tester,
    ) async {
      final dirty = await pump(
        tester,
        const EditableFile(text: 'on disk now'),
        draft: const EditorDraft(
          text: 'typed earlier',
          baseline: EditableFile(text: 'abc'),
        ),
      );

      expect(find.text('typed earlier'), findsOneWidget);
      expect(dirty, [true]);
    });

    testWidgets('dirtiness is measured against the draft\'s baseline', (
      tester,
    ) async {
      final drafts = <EditorDraft?>[];
      final dirty = await pump(
        tester,
        const EditableFile(text: 'on disk now'),
        draft: const EditorDraft(
          text: 'typed earlier',
          baseline: EditableFile(text: 'abc'),
        ),
        onDraftChanged: drafts.add,
      );

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      expect(dirty.last, isFalse);
      expect(drafts.last, isNull);
    });
  });

  testWidgets('save still works while the file is shown rendered', (
    tester,
  ) async {
    final rendered = ValueNotifier(false);
    addTearDown(rendered.dispose);
    final saved = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editableFileForPathProvider.overrideWith(
            (ref, FileRef _) async => const EditableFile(text: 'abc'),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: rendered,
              builder: (context, on, _) => FileTextEditor(
                repoPath: '/r',
                relPath: 'README.md',
                onSave: (path, text) async {
                  saved.add(text);
                  return true;
                },
                renderedBuilder: on ? (context, text) => Text('R:$text') : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();

    rendered.value = true;
    await tester.pumpAndSettle();
    expect(find.text('R:abcd'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(saved, ['abcd']);
  });
}
