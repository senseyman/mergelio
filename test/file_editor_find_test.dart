// The editor's line-number gutter and its find/replace bar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/ui/common/file_text_editor.dart';

void main() {
  Future<void> pump(WidgetTester tester, String text) async {
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
          home: const Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: FileTextEditor(repoPath: '/r', relPath: 'lib/main.dart'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The editor's own text field, told apart from the find bar's.
  final body = find.byKey(const ValueKey('editor:body'));

  Finder gutterLine(String n) => find.descendant(
    of: find.byKey(const ValueKey('editor:gutter')),
    matching: find.text(n),
  );

  Future<void> openFind(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
  }

  Future<void> query(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const ValueKey('find:query')), q);
    await tester.pumpAndSettle();
  }

  testWidgets('every line is numbered beside the text', (tester) async {
    await pump(tester, 'one\ntwo\nthree');

    expect(gutterLine('1'), findsOneWidget);
    expect(gutterLine('3'), findsOneWidget);
    expect(gutterLine('4'), findsNothing);
  });

  testWidgets('the numbering follows the text as it is typed', (tester) async {
    await pump(tester, 'one');
    expect(gutterLine('2'), findsNothing);

    await tester.enterText(body, 'one\ntwo');
    await tester.pumpAndSettle();

    expect(gutterLine('2'), findsOneWidget);
  });

  testWidgets('Ctrl+F opens the find bar and Escape closes it', (tester) async {
    await pump(tester, 'one two');

    await openFind(tester);
    expect(find.byKey(const ValueKey('find:query')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('find:query')), findsNothing);
  });

  testWidgets('the bar reports how many matches there are', (tester) async {
    await pump(tester, 'one two one');

    await openFind(tester);
    await query(tester, 'one');

    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('a query that matches nothing says so', (tester) async {
    await pump(tester, 'one two');

    await openFind(tester);
    await query(tester, 'three');

    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('next walks the matches and wraps around', (tester) async {
    await pump(tester, 'one two one');

    await openFind(tester);
    await query(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('find:next')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('find:next')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('the current match is selected in the text', (tester) async {
    await pump(tester, 'one two one');

    await openFind(tester);
    await query(tester, 'two');

    final field = tester.widget<TextField>(body);
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 4, extentOffset: 7),
    );
  });

  testWidgets('replace all rewrites every match', (tester) async {
    await pump(tester, 'one two one');

    await openFind(tester);
    await query(tester, 'one');
    await tester.enterText(find.byKey(const ValueKey('find:replace')), 'ONE');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('find:replaceAll')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(body).controller!.text, 'ONE two ONE');
  });

  testWidgets('matching ignores case until the toggle is turned on', (
    tester,
  ) async {
    await pump(tester, 'One one');

    await openFind(tester);
    await query(tester, 'one');
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('find:case')));
    await tester.pumpAndSettle();

    expect(find.text('1 of 1'), findsOneWidget);
  });
}
