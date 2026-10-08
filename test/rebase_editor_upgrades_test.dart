import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/rebase/rebase_editor.dart';

void main() {
  RebasePlan? result;
  var closed = false;

  setUp(() {
    result = null;
    closed = false;
  });

  RebaseStep pick(String sha, String message) =>
      RebaseStep(sha, RebaseAction.pick, message: message);

  Widget harness(List<RebaseStep> initial, List<String> stacked) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showRebaseEditor(
                context,
                steps: initial,
                onto: 'a1b2c3d',
                stackedBranches: stacked,
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Future<void> open(
    WidgetTester tester,
    List<RebaseStep> initial, {
    List<String> stacked = const [],
  }) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(initial, stacked));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) => tapText(tester, 'Start rebase');

  List<String> ids(RebasePlan? p) => [for (final s in p!.steps) s.id];

  final withFixup = [
    pick('aaa', 'Add login'),
    pick('bbb', 'Add logout'),
    pick('fff', 'fixup! Add login'),
  ];

  group('autosquash', () {
    testWidgets('is not offered when no commit asks for it', (tester) async {
      await open(tester, [pick('aaa', 'A'), pick('bbb', 'B')]);
      expect(find.text('Fold fixup commits into their targets'), findsNothing);
    });

    testWidgets('says how many commits it found', (tester) async {
      await open(tester, withFixup);
      expect(find.text('Fold fixup commits into their targets'), findsOne);
      expect(find.textContaining('1 fixup!/squash! commit'), findsOne);
    });

    testWidgets('turning it on reorders the plan and shows the pairing', (
      tester,
    ) async {
      await open(tester, withFixup);
      await tapText(tester, 'Fold fixup commits into their targets');

      // The per-commit table opens so the pairing is visible.
      expect(find.text('fixup! Add login'), findsOne);
      expect(find.text('↳ into Add login'), findsOne);
      await start(tester);
      expect(ids(result), ['aaa', 'fff', 'bbb']);
      expect(result!.steps[1].action, RebaseAction.fixup);
    });

    testWidgets('turning it off puts the commits back', (tester) async {
      await open(tester, withFixup);
      await tapText(tester, 'Fold fixup commits into their targets');
      await tapText(tester, 'Fold fixup commits into their targets');
      await start(tester);

      expect(ids(result), ['aaa', 'bbb', 'fff']);
      expect(result!.steps.every((s) => s.action == RebaseAction.pick), isTrue);
    });

    testWidgets('a preset chosen afterwards undoes it first', (tester) async {
      await open(tester, withFixup);
      await tapText(tester, 'Fold fixup commits into their targets');
      await tapText(tester, 'Move commits as-is');
      await start(tester);

      expect(ids(result), ['aaa', 'bbb', 'fff']);
    });
  });

  group('stacked branches', () {
    testWidgets('are not offered when none sit on the commits', (tester) async {
      await open(tester, [pick('aaa', 'A')]);
      expect(find.text('Move stacked branches too'), findsNothing);
      await start(tester);
      expect(result!.updateRefs, isFalse);
    });

    testWidgets('are named, off by default, and opt-in', (tester) async {
      await open(tester, [pick('aaa', 'A')], stacked: ['part-1', 'part-2']);
      expect(find.text('Move stacked branches too'), findsOne);
      expect(find.textContaining('part-1, part-2'), findsOne);

      await tapText(tester, 'Move stacked branches too');
      await start(tester);
      expect(result!.updateRefs, isTrue);
    });
  });

  group('exec and break', () {
    Future<void> customize(WidgetTester tester) =>
        tapText(tester, 'Customize per commit');

    testWidgets('an exec step is shown in full and confirmed before it runs', (
      tester,
    ) async {
      await open(tester, [pick('aaa', 'A')]);
      await customize(tester);
      await tapText(tester, 'Add exec step');
      await tester.enterText(
        find.byKey(const ValueKey('rebase-exec-field-exec1')),
        "flutter test --name 'login'",
      );
      await tester.pumpAndSettle();
      await start(tester);

      // Not started yet: the command is shown verbatim first.
      expect(closed, isFalse);
      expect(find.text('Run these commands?'), findsOne);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text("flutter test --name 'login'"),
        ),
        findsOne,
      );
      await tapText(tester, 'Run rebase');

      expect(result!.steps.last.action, RebaseAction.exec);
      expect(result!.steps.last.command, "flutter test --name 'login'");
    });

    testWidgets('backing out of the confirmation keeps the editor open', (
      tester,
    ) async {
      await open(tester, [pick('aaa', 'A')]);
      await customize(tester);
      await tapText(tester, 'Add exec step');
      await tester.enterText(
        find.byKey(const ValueKey('rebase-exec-field-exec1')),
        'make',
      );
      await tester.pumpAndSettle();
      await start(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(find.text('Interactive rebase'), findsOne);
    });

    testWidgets('an exec with no command cannot start', (tester) async {
      await open(tester, [pick('aaa', 'A')]);
      await customize(tester);
      await tapText(tester, 'Add exec step');

      final startButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start rebase'),
      );
      expect(startButton.onPressed, isNull);
      expect(find.text('An exec step has no command to run.'), findsOne);
    });

    testWidgets('a break needs no confirmation', (tester) async {
      await open(tester, [pick('aaa', 'A')]);
      await customize(tester);
      await tapText(tester, 'Add break');
      await start(tester);

      expect(result!.steps.map((s) => s.action), [
        RebaseAction.pick,
        RebaseAction.breakpoint,
      ]);
    });

    testWidgets('an added step can be removed again', (tester) async {
      await open(tester, [pick('aaa', 'A')]);
      await customize(tester);
      await tapText(tester, 'Add break');
      await tester.tap(find.byTooltip('Remove step'));
      await tester.pumpAndSettle();
      await start(tester);

      expect(ids(result), ['aaa']);
    });

    testWidgets('an exec row being typed in can be removed', (tester) async {
      await open(tester, [pick('aaa', 'A')]);
      await customize(tester);
      await tapText(tester, 'Add exec step');
      await tester.enterText(
        find.byKey(const ValueKey('rebase-exec-field-exec1')),
        'make',
      );
      await tester.tap(find.byTooltip('Remove step'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await start(tester);

      expect(ids(result), ['aaa']);
    });

    testWidgets('a break row does not make one commit squashable', (
      tester,
    ) async {
      await open(tester, [pick('aaa', 'A')]);
      await customize(tester);
      await tapText(tester, 'Add break');

      final squash = tester.widget<RadioListTile<RebasePreset>>(
        find.widgetWithText(
          RadioListTile<RebasePreset>,
          'Squash into one commit',
        ),
      );
      expect(squash.enabled, isFalse);
    });

    testWidgets('steps it adds never reuse an id already in the plan', (
      tester,
    ) async {
      await open(tester, [
        pick('aaa', 'A'),
        const RebaseStep.exec('make', id: 'exec1'),
      ]);
      await customize(tester);
      await tapText(tester, 'Add exec step');
      final added = tester.widgetList<TextField>(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.key as ValueKey?)?.value.toString().startsWith(
                    'rebase-exec-field-',
                  ) ==
                  true,
        ),
      );
      expect(added.map((f) => f.key).toSet(), hasLength(2));
      expect(added.last.controller?.text, isEmpty);
    });

    testWidgets('a preset keeps exec and break steps', (tester) async {
      await open(tester, [pick('aaa', 'A'), pick('bbb', 'B')]);
      await customize(tester);
      await tapText(tester, 'Add break');
      await tapText(tester, 'Squash into one commit');
      await start(tester);

      expect(result!.steps.map((s) => s.action), [
        RebaseAction.pick,
        RebaseAction.squash,
        RebaseAction.breakpoint,
      ]);
    });
  });
}
