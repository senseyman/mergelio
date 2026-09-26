import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/graph/bisect_run_dialog.dart';

void main() {
  Future<String?> open(WidgetTester tester, {String? type}) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  result = await showBisectRunDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (type != null) {
      await tester.enterText(find.byType(TextField), type);
      await tester.pumpAndSettle();
    }
    return result;
  }

  testWidgets('Run is disabled until a command is typed', (tester) async {
    await open(tester);
    final run = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Run'),
    );
    expect(run.onPressed, isNull);
  });

  testWidgets('the dialog shows the command line that will execute', (
    tester,
  ) async {
    await open(tester, type: 'make check');
    // Not just the typed text: the shell wrapper is shown too, so there is no
    // gap between what was typed and what runs.
    expect(find.textContaining('make check'), findsWidgets);
    expect(find.textContaining('-c'), findsWidgets);
  });

  testWidgets('the dialog warns that a tree-modifying command breaks the run', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('modifies tracked files'), findsOneWidget);
  });

  testWidgets('cancelling returns null', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  result = await showBisectRunDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('running returns exactly the typed command, unwrapped', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  result = await showBisectRunDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'make check');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pumpAndSettle();
    // The caller receives exactly what was typed, unwrapped — not the shell
    // wrapper shown in the preview.
    expect(result, 'make check');
    expect(find.byType(TextField), findsNothing);
  });
}
