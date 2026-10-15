import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/clone_options.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_bootstrap.dart';
import 'package:mergelio/ui/welcome/repo_dialogs.dart';

/// Captures what the dialog asks for instead of cloning.
class _FakeBootstrap extends RepoBootstrap {
  _FakeBootstrap(super.ref);
  CloneOptions? options;
  String? url;

  @override
  Future<String?> clone({
    required String url,
    required String parentDir,
    String? folderName,
    CloneOptions options = const CloneOptions(),
  }) async {
    this.url = url;
    this.options = options;
    return null;
  }
}

void main() {
  late _FakeBootstrap boot;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repoBootstrapProvider.overrideWith(
            (ref) => boot = _FakeBootstrap(ref),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCloneDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The destination comes from a folder picker; fill it directly, then type
    // the URL so the dialog rebuilds with both.
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    fields.elementAt(2).controller!.text = '/tmp/dest';
    await tester.enterText(find.byType(TextField).first, 'https://h/a/r.git');
    await tester.pump();
  }

  Finder check(String label) =>
      find.widgetWithText(CheckboxListTile, label, skipOffstage: false);

  FilledButton cloneButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Clone'));

  testWidgets('options start hidden and default to a plain clone', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Shallow clone'), findsNothing);

    await tester.tap(find.text('Clone options'));
    await tester.pumpAndSettle();
    expect(find.text('Shallow clone'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(check('Include submodules')).value,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Clone'));
    await tester.pump();
    final o = boot.options!;
    expect(o.depth, isNull);
    expect(o.blobless, isFalse);
    expect(o.branch, anyOf(isNull, isEmpty));
    expect(o.singleBranch, isFalse);
    expect(o.submodules, isTrue);
  });

  testWidgets('passes every option the user set', (tester) async {
    await open(tester);
    await tester.tap(find.text('Clone options'));
    await tester.pumpAndSettle();

    await tester.tap(check('Shallow clone'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('clone-depth')), '5');
    await tester.tap(check('Blobless: fetch file contents on demand'));
    await tester.enterText(find.byKey(const ValueKey('clone-branch')), 'dev');
    await tester.tap(check('Only this branch'));
    await tester.tap(check('Include submodules'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Clone'));
    await tester.pump();
    final o = boot.options!;
    expect(o.depth, 5);
    expect(o.blobless, isTrue);
    expect(o.branch, 'dev');
    expect(o.singleBranch, isTrue);
    expect(o.submodules, isFalse);
  });

  testWidgets('depth only counts while shallow is ticked', (tester) async {
    await open(tester);
    await tester.tap(find.text('Clone options'));
    await tester.pumpAndSettle();
    await tester.tap(check('Shallow clone'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('clone-depth')), '7');
    await tester.tap(check('Shallow clone'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Clone'));
    await tester.pump();
    expect(boot.options!.depth, isNull);
  });

  testWidgets('a bad depth or branch blocks the clone and says why', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Clone options'));
    await tester.pumpAndSettle();
    await tester.tap(check('Shallow clone'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('clone-depth')), '0');
    await tester.pump();
    expect(cloneButton(tester).onPressed, isNull);
    expect(find.text('Depth must be a positive number'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('clone-depth')), '2');
    await tester.enterText(find.byKey(const ValueKey('clone-branch')), '-x');
    await tester.pump();
    expect(cloneButton(tester).onPressed, isNull);
    expect(find.text('Not a valid branch name'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('clone-branch')), 'x');
    await tester.pump();
    expect(cloneButton(tester).onPressed, isNotNull);
  });
}
