// Undo inside an open editor. The app binds ⌘Z to the repository's undo, so
// without a binding of its own the editor would answer a typing mistake by
// reverting the last git operation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/ui/common/file_text_editor.dart';

void main() {
  /// What an app-level ⌘Z would have done, had the editor let it through.
  var repoUndos = 0;

  Future<void> pump(WidgetTester tester, String text) async {
    repoUndos = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editableFileForPathProvider.overrideWith(
            (ref, FileRef _) async => EditableFile(text: text),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  control: true,
                ): () =>
                    repoUndos++,
              },
              child: const SizedBox(
                width: 600,
                height: 400,
                child: FileTextEditor(repoPath: '/r', relPath: 'lib/main.dart'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The undo stack records the text it starts from only after the editor has
    // held focus quietly for a moment; typing before that leaves nothing to go
    // back to.
    await tester.pump(const Duration(milliseconds: 600));
  }

  final body = find.byKey(const ValueKey('editor:body'));

  Future<void> press(WidgetTester tester, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
  }

  /// Sends the edit the way a keystroke arrives, through the text input
  /// channel — the route the undo stack records. Undo entries are throttled,
  /// so the change then needs a moment of quiet to become undoable on its own.
  Future<void> type(WidgetTester tester, String text) async {
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester) =>
      tester.widget<TextField>(body).controller!.text;

  testWidgets('Ctrl+Z takes back the last edit rather than the last commit', (
    tester,
  ) async {
    await pump(tester, 'first\n');
    await type(tester, 'first\nsecond\n');

    await press(tester);

    expect(textOf(tester), 'first\n');
    expect(repoUndos, 0);
  });

  testWidgets('Ctrl+Shift+Z puts the undone edit back', (tester) async {
    await pump(tester, 'first\n');
    await type(tester, 'first\nsecond\n');
    await press(tester);

    await press(tester, shift: true);

    expect(textOf(tester), 'first\nsecond\n');
  });
}
