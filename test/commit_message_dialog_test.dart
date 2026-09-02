import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/ui/common/dialogs.dart';

void main() {
  CommitMessageParts? result;
  var called = false;

  setUp(() {
    result = null;
    called = false;
  });

  Widget harness({String summary = '', String description = ''}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showCommitMessageDialog(
                context,
                initialSummary: summary,
                initialDescription: description,
              );
              called = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('both fields are pre-filled from the existing message', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(summary: 'Old subject', description: 'Old body'),
    );
    await open(tester);

    expect(find.text('Old subject'), findsOneWidget);
    expect(find.text('Old body'), findsOneWidget);
  });

  testWidgets('saving returns the edited summary and description', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(summary: 'Old subject', description: 'Old body'),
    );
    await open(tester);

    await tester.enterText(find.byType(TextField).first, 'New subject');
    await tester.enterText(find.byType(TextField).last, 'New body');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result?.summary, 'New subject');
    expect(result?.description, 'New body');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling returns null', (tester) async {
    await tester.pumpWidget(harness(summary: 'Old subject'));
    await open(tester);

    await tester.enterText(find.byType(TextField).first, 'typed');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an emptied summary cannot be saved', (tester) async {
    await tester.pumpWidget(harness(summary: 'Old subject'));
    await open(tester);

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Still open, nothing returned — a commit with no subject is not a commit.
    expect(find.text('Save'), findsOneWidget);
    expect(called, isFalse);
  });

  testWidgets('the description field takes multiple lines', (tester) async {
    await tester.pumpWidget(harness(summary: 'Subject'));
    await open(tester);

    await tester.enterText(find.byType(TextField).last, 'line one\nline two');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result?.description, 'line one\nline two');
  });
}
