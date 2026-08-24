import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/ui/rebase/rebase_editor.dart';

void main() {
  List<RebaseStep>? result;

  setUp(() => result = null);

  List<RebaseStep> steps(int n) => [
    for (var i = 0; i < n; i++)
      RebaseStep('sha$i', RebaseAction.pick, message: 'commit $i'),
  ];

  Widget harness(List<RebaseStep> initial, {String onto = 'a1b2c3d'}) =>
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => result = await showRebaseEditor(
                  context,
                  steps: initial,
                  onto: onto,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester, List<RebaseStep> initial) async {
    await tester.pumpWidget(harness(initial));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text('Start rebase'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the whole-branch default, not a per-commit list', (
    tester,
  ) async {
    await open(tester, steps(3));

    expect(find.text('Move commits as-is'), findsOneWidget);
    // The per-commit rows stay collapsed until the user asks for them.
    expect(find.text('commit 0'), findsNothing);
    expect(find.byType(DropdownButton<RebaseAction>), findsNothing);
  });

  testWidgets('every preset explains what it does', (tester) async {
    await open(tester, steps(3));

    expect(find.textContaining('Replay all 3 commits'), findsOneWidget);
    expect(find.textContaining('all messages are kept'), findsOneWidget);
    expect(find.textContaining('only the first message'), findsOneWidget);
  });

  testWidgets('the header says how many commits move and where', (
    tester,
  ) async {
    await open(tester, steps(3));

    expect(find.textContaining('3 commits onto a1b2c3d'), findsOneWidget);
  });

  testWidgets('accepting the default returns an all-pick plan', (tester) async {
    await open(tester, steps(3));
    await start(tester);

    expect(result?.map((s) => s.action), [
      RebaseAction.pick,
      RebaseAction.pick,
      RebaseAction.pick,
    ]);
  });

  testWidgets('choosing a squash preset returns pick + squashes', (
    tester,
  ) async {
    await open(tester, steps(3));
    await tester.tap(find.text('Squash into one commit'));
    await tester.pumpAndSettle();
    await start(tester);

    expect(result?.map((s) => s.action), [
      RebaseAction.pick,
      RebaseAction.squash,
      RebaseAction.squash,
    ]);
  });

  testWidgets('choosing keep-first returns pick + fixups', (tester) async {
    await open(tester, steps(3));
    await tester.tap(find.text('Squash, keep first message'));
    await tester.pumpAndSettle();
    await start(tester);

    expect(result?.map((s) => s.action), [
      RebaseAction.pick,
      RebaseAction.fixup,
      RebaseAction.fixup,
    ]);
  });

  testWidgets('customize reveals the per-commit rows and the legend', (
    tester,
  ) async {
    await open(tester, steps(2));
    await tester.tap(find.text('Customize per commit'));
    await tester.pumpAndSettle();

    expect(find.text('commit 0'), findsOneWidget);
    expect(find.text('commit 1'), findsOneWidget);
    expect(find.textContaining('merge into the commit above'), findsWidgets);
  });

  testWidgets('customize starts from the plan the preset produced', (
    tester,
  ) async {
    await open(tester, steps(2));
    await tester.tap(find.text('Squash into one commit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize per commit'));
    await tester.pumpAndSettle();
    await start(tester);

    // Switching to customize extends the preset rather than resetting it.
    expect(result?.map((s) => s.action), [
      RebaseAction.pick,
      RebaseAction.squash,
    ]);
  });

  testWidgets('a per-commit action can be changed in customize mode', (
    tester,
  ) async {
    await open(tester, steps(2));
    await tester.tap(find.text('Customize per commit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<RebaseAction>).last);
    await tester.pumpAndSettle();
    // The legend carries the same wording, so the open menu entry is the last.
    await tester.tap(find.textContaining('drop — remove this commit').last);
    await tester.pumpAndSettle();
    await start(tester);

    expect(result?.last.action, RebaseAction.drop);
  });

  testWidgets('the dropdown spells out what each action means', (tester) async {
    await open(tester, steps(2));
    await tester.tap(find.text('Customize per commit'));
    await tester.pumpAndSettle();
    // Closed, only the legend spells the actions out.
    expect(find.textContaining('drop — remove this commit'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<RebaseAction>).first);
    await tester.pumpAndSettle();

    // Open, each menu entry repeats its own meaning next to the git word.
    expect(find.textContaining('drop — remove this commit'), findsNWidgets(2));
    expect(
      find.textContaining('reword — keep this commit, change its message'),
      findsNWidgets(2),
    );
  });

  testWidgets('a single commit cannot be squashed', (tester) async {
    await open(tester, steps(1));

    final tile = tester.widget<RadioListTile<RebasePreset>>(
      find.widgetWithText(
        RadioListTile<RebasePreset>,
        'Squash into one commit',
      ),
    );
    expect(tile.enabled, isFalse);
    expect(find.textContaining('Needs at least 2 commits'), findsWidgets);
  });

  testWidgets('cancelling returns null', (tester) async {
    await open(tester, steps(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plan that squashes the first commit cannot be started', (
    tester,
  ) async {
    await open(tester, steps(2));
    await tester.tap(find.text('Customize per commit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<RebaseAction>).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining('squash — merge into the commit above').last,
    );
    await tester.pumpAndSettle();

    // git would reject this todo and strand the repository mid-rebase.
    expect(find.textContaining('no commit above it'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start rebase'),
    );
    expect(button.onPressed, isNull);

    await start(tester);
    expect(result, isNull);
    expect(find.text('Start rebase'), findsOneWidget); // still open
  });

  testWidgets('fixing the first action re-enables Start', (tester) async {
    await open(tester, steps(2));
    await tester.tap(find.text('Customize per commit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<RebaseAction>).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining('squash — merge into the commit above').last,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<RebaseAction>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('drop — remove this commit').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('no commit above it'), findsNothing);
    await start(tester);
    expect(result?.first.action, RebaseAction.drop);
  });
}
