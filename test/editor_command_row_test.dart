import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/external_tools.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/preferences/editor_command_row.dart';

/// Preferences → General → Open files with: presets for the common editors,
/// and a free command for anything else.
void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    String command = '',
    Locale locale = const Locale('en'),
    double width = 560,
  }) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <String>[];
    var current = command;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EditorCommandRow(
              command: current,
              onChanged: (v) {
                saved.add(v);
                setState(() => current = v);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return saved;
  }

  bool selected(WidgetTester tester, String label) => tester
      .widget<ChoiceChip>(
        find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)),
      )
      .selected;

  testWidgets('an empty command is the system default', (tester) async {
    await pump(tester);
    expect(selected(tester, 'System default'), isTrue);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a preset chip saves its command', (tester) async {
    final saved = await pump(tester);
    await tester.tap(find.text('VS Code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IntelliJ IDEA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    expect(saved, [kVsCodeEditor, kIdeaEditor, '']);
  });

  testWidgets('a preset command selects its chip', (tester) async {
    await pump(tester, command: kIdeaEditor);
    expect(selected(tester, 'IntelliJ IDEA'), isTrue);
    expect(selected(tester, 'Custom'), isFalse);
  });

  testWidgets('any other command is custom, and editable', (tester) async {
    final saved = await pump(tester, command: 'subl -n');
    expect(selected(tester, 'Custom'), isTrue);
    expect(find.widgetWithText(TextField, 'subl -n'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zed {file}:{line}');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved, ['zed {file}:{line}']);
    expect(find.textContaining('{file}'), findsWidgets);
  });

  testWidgets('custom starts from the preset in use, saving nothing yet', (
    tester,
  ) async {
    final saved = await pump(tester, command: kVsCodeEditor);
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(selected(tester, 'Custom'), isTrue);
    expect(find.widgetWithText(TextField, kVsCodeEditor), findsOneWidget);
  });

  testWidgets('fits the narrow dialog, in Ukrainian too', (tester) async {
    for (final width in [336.0, 560.0]) {
      await pump(
        tester,
        command: 'x',
        locale: const Locale('uk'),
        width: width,
      );
      expect(tester.takeException(), isNull, reason: '$width');
    }
    expect(find.text('Відкривати файли в'), findsOneWidget);
  });
}
