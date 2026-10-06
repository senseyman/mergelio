// The window git and ssh get instead of a terminal they cannot reach.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/askpass/askpass_prompt.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    String prompt, {
    void Function(String)? onAnswer,
    VoidCallback? onCancel,
    ({String name, String path})? repo,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [AppTokens.dark()]),
      home: AskpassPrompt(
        prompt: prompt,
        repo: repo,
        onAnswer: onAnswer ?? (_) {},
        onCancel: onCancel ?? () {},
      ),
    ),
  );

  testWidgets('shows the prompt git or ssh asked with', (tester) async {
    await pump(tester, "Enter passphrase for key '/k/id_ed25519': ");

    expect(find.textContaining('id_ed25519'), findsOneWidget);
  });

  testWidgets('names the repository that is asking', (tester) async {
    await pump(
      tester,
      "Username for 'https://github.com': ",
      repo: (name: 'api', path: '/work/services/api'),
    );

    expect(find.text('api'), findsOneWidget);
    expect(find.text('/work/services/api'), findsOneWidget);
    // git's own prompt is still shown as it was.
    expect(find.textContaining('github.com'), findsOneWidget);
  });

  testWidgets('without a repository nothing extra is shown', (tester) async {
    await pump(tester, "Username for 'https://github.com': ");

    expect(find.byIcon(Icons.folder_outlined), findsNothing);
  });

  testWidgets('fits the smallest window, named repository or not', (
    tester,
  ) async {
    // The askpass window's minimum size.
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final repo in [
      null,
      (
        name: 'a-repository-with-a-rather-long-folder-name',
        path:
            '/Users/someone/work/clients/acme/services/'
            'a-repository-with-a-rather-long-folder-name',
      ),
    ]) {
      await pump(tester, "Username for 'https://github.com': ", repo: repo);
      expect(tester.takeException(), isNull, reason: 'repo: $repo');
    }
  });

  testWidgets('hides a passphrase while it is typed', (tester) async {
    await pump(tester, "Enter passphrase for key '/k/id_ed25519': ");

    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
  });

  testWidgets('leaves a username readable', (tester) async {
    await pump(tester, "Username for 'https://github.com': ");

    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );
  });

  testWidgets('hands the typed secret over', (tester) async {
    String? answered;
    await pump(tester, 'Password: ', onAnswer: (v) => answered = v);

    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(answered, 'hunter2');
  });

  testWidgets('cancelling answers nothing', (tester) async {
    var cancelled = false;
    String? answered;
    await pump(
      tester,
      'Password: ',
      onAnswer: (v) => answered = v,
      onCancel: () => cancelled = true,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelled, isTrue);
    expect(answered, isNull);
  });

  testWidgets('escape declines, rather than answering with an empty value', (
    tester,
  ) async {
    var cancelled = false;
    String? answered;
    await pump(
      tester,
      'Password: ',
      onAnswer: (v) => answered = v,
      onCancel: () => cancelled = true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(cancelled, isTrue);
    expect(answered, isNull);
  });

  testWidgets('answers a host-key question with a word, not a secret', (
    tester,
  ) async {
    String? answered;
    await pump(
      tester,
      'The authenticity of host example.com can\'t be established. '
      'Are you sure you want to continue connecting (yes/no/[fingerprint])? ',
      onAnswer: (v) => answered = v,
    );

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Yes'));
    await tester.pump();

    expect(answered, 'yes');
  });

  testWidgets('declining a host key says no rather than hanging up', (
    tester,
  ) async {
    String? answered;
    await pump(
      tester,
      'Are you sure you want to continue connecting (yes/no)? ',
      onAnswer: (v) => answered = v,
    );

    await tester.tap(find.text('No'));
    await tester.pump();

    expect(answered, 'no');
  });
}
