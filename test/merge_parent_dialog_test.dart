import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/shell/repo_op_dialogs.dart';

/// The picker that supplies `-m` when a merge commit is reverted or picked.
void main() {
  final merge = Commit(
    sha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    message: 'merge feature',
    author: 'Tester',
    authorEmail: 't@example.com',
    date: DateTime(2026, 9, 8),
    parents: const [
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'cccccccccccccccccccccccccccccccccccccccc',
    ],
  );

  int? result;
  var returned = false;

  setUp(() {
    result = null;
    returned = false;
  });

  Widget harness({MainlineOp op = MainlineOp.revert}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showMainlineDialog(
                context,
                commit: merge,
                op: op,
                subjects: const {
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb': 'main work',
                  'cccccccccccccccccccccccccccccccccccccccc': 'feature work',
                },
              );
              returned = true;
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

  testWidgets('lists every parent with its short sha and subject', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await open(tester);

    expect(find.textContaining('bbbbbbb'), findsOneWidget);
    expect(find.textContaining('ccccccc'), findsOneWidget);
    expect(find.text('main work'), findsOneWidget);
    expect(find.text('feature work'), findsOneWidget);
  });

  testWidgets('confirming without touching the list returns parent 1', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await open(tester);

    await tester.tap(find.text('Revert'));
    await tester.pumpAndSettle();

    expect(result, 1);
  });

  testWidgets('choosing the second parent returns 2', (tester) async {
    await tester.pumpWidget(harness());
    await open(tester);

    await tester.tap(find.text('feature work'));
    await tester.pump();
    await tester.tap(find.text('Revert'));
    await tester.pumpAndSettle();

    expect(result, 2);
  });

  testWidgets('cancelling returns null', (tester) async {
    await tester.pumpWidget(harness());
    await open(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNull);
  });

  testWidgets('the cherry-pick variant confirms with its own label', (
    tester,
  ) async {
    await tester.pumpWidget(harness(op: MainlineOp.cherryPick));
    await open(tester);

    expect(find.text('Revert'), findsNothing);
    await tester.tap(find.text('Cherry-pick'));
    await tester.pumpAndSettle();

    expect(result, 1);
  });

  Commit c(
    String sha, {
    String message = 'x',
    List<String> parents = const [],
  }) => Commit(
    sha: sha,
    message: message,
    author: 'Tester',
    authorEmail: 't@example.com',
    date: DateTime(2026, 9, 8),
    parents: parents,
  );

  test('only a commit with two or more parents needs a mainline', () {
    expect(needsMainline(c('a')), isFalse);
    expect(needsMainline(c('a', parents: ['b'])), isFalse);
    expect(needsMainline(c('a', parents: ['b', 'c'])), isTrue);
    expect(needsMainline(c('a', parents: ['b', 'c', 'd'])), isTrue);
  });

  test('parent subjects are looked up by sha, unknown parents skipped', () {
    final loaded = [
      c('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', message: 'main work'),
      c('dddddddddddddddddddddddddddddddddddddddd', message: 'unrelated'),
    ];

    expect(parentSubjects(merge, loaded), {
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb': 'main work',
    });
  });
}
