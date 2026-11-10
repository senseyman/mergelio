import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/workspace/add_submodule_dialog.dart';

/// The add-submodule form: the path it suggests from the URL, when it lets
/// the user submit, and what it returns.
void main() {
  AddSubmoduleData? result;
  var returned = false;

  setUp(() {
    result = null;
    returned = false;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showAddSubmoduleDialog(context);
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(int i) => find.byType(TextField).at(i);
  Finder url() => field(0);
  Finder path() => field(1);
  Finder branch() => field(2);

  String text(WidgetTester tester, Finder f) =>
      tester.widget<TextField>(f).controller!.text;

  FilledButton addButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'));

  testWidgets('opens titled, empty, with Add disabled', (tester) async {
    await open(tester);
    expect(find.text('Add submodule'), findsOneWidget);
    expect(text(tester, url()), isEmpty);
    expect(addButton(tester).onPressed, isNull);
  });

  for (final (input, expected) in [
    ('https://github.com/acme/lib.git', 'lib'),
    ('https://github.com/acme/lib', 'lib'),
    ('https://github.com/acme/lib/', 'lib'),
    ('git@github.com:acme/tools.git', 'tools'),
    (r'C:\src\vendor\dep.git', 'dep'),
    ('  https://host/x/y.git  ', 'y'),
  ]) {
    testWidgets('suggests "$expected" as the path for $input', (tester) async {
      await open(tester);
      await tester.enterText(url(), input);
      await tester.pump();
      expect(text(tester, path()), expected);
    });
  }

  testWidgets('clearing the URL clears the suggested path', (tester) async {
    await open(tester);
    await tester.enterText(url(), 'https://h/a/lib.git');
    await tester.pump();
    await tester.enterText(url(), '');
    await tester.pump();
    expect(text(tester, path()), isEmpty);
    expect(addButton(tester).onPressed, isNull);
  });

  testWidgets('a hand-edited path is no longer overwritten by the URL', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(url(), 'https://h/a/lib.git');
    await tester.pump();
    await tester.enterText(path(), 'vendor/lib');
    await tester.pump();
    await tester.enterText(url(), 'https://h/a/other.git');
    await tester.pump();
    expect(text(tester, path()), 'vendor/lib');
  });

  testWidgets('Add stays disabled while the path is blank', (tester) async {
    await open(tester);
    await tester.enterText(url(), 'https://h/a/lib.git');
    await tester.pump();
    await tester.enterText(path(), '   ');
    await tester.pump();
    expect(addButton(tester).onPressed, isNull);

    // Enter in a field cannot slip past the check either.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(returned, isFalse);
  });

  testWidgets('Add returns trimmed values and no branch when left blank', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(url(), ' https://h/a/lib.git ');
    await tester.pump();
    await tester.enterText(branch(), '   ');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, (url: 'https://h/a/lib.git', path: 'lib', branch: null));
  });

  testWidgets('a branch is returned trimmed', (tester) async {
    await open(tester);
    await tester.enterText(url(), 'https://h/a/lib.git');
    await tester.enterText(branch(), ' release/2.x ');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(result?.branch, 'release/2.x');
  });

  testWidgets('Enter submits a valid form', (tester) async {
    await open(tester);
    await tester.enterText(url(), 'https://h/a/lib.git');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, (url: 'https://h/a/lib.git', path: 'lib', branch: null));
  });

  testWidgets('Cancel returns null', (tester) async {
    await open(tester);
    await tester.enterText(url(), 'https://h/a/lib.git');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
  });
}
