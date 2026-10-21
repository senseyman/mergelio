import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/workspace/edit_note.dart';

void main() {
  late String? result;
  late bool closed;

  Future<void> open(WidgetTester tester, {String initial = ''}) async {
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showNoteDialog(context, initial: initial);
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a commit without a note gets an add dialog', (tester) async {
    await open(tester);
    expect(find.text('Add note'), findsOneWidget);
    // Notes are not carried by an ordinary push; the dialog says so.
    expect(find.textContaining('push them'), findsOneWidget);
  });

  testWidgets('an existing note is prefilled and saved as edited', (
    tester,
  ) async {
    await open(tester, initial: 'old text');
    expect(find.text('Edit note'), findsOneWidget);
    expect(find.text('old text'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'line one\n\nline three');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, 'line one\n\nline three');
  });

  testWidgets('saving an emptied note returns empty, not a cancel', (
    tester,
  ) async {
    await open(tester, initial: 'old text');
    await tester.enterText(find.byType(TextField), '  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, '');
  });

  testWidgets('cancel returns null', (tester) async {
    await open(tester, initial: 'old text');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });
}
