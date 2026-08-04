// One editing widget backs both the diff sheet and Files mode, so the guards,
// the dirty tracking and the save path cannot drift apart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/ui/common/file_text_editor.dart';

void main() {
  Future<List<bool>> pump(
    WidgetTester tester,
    EditableFile file, {
    Future<bool> Function(String path, String text)? onSave,
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
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: FileTextEditor(
              repoPath: '/r',
              relPath: 'lib/main.dart',
              onDirtyChanged: dirty.add,
              onSave: onSave,
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
}
