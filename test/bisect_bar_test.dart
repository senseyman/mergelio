import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/ui/graph/bisect_bar.dart';

BisectState _state({
  required List<BisectMark> marks,
  int left = -1,
  int steps = -1,
  String? firstBad,
}) => BisectState(
  marks: marks,
  terms: const BisectTerms(),
  currentSha: 'head1111',
  revisionsLeft: left,
  steps: steps,
  firstBad: firstBad,
);

Future<void> _pump(
  WidgetTester tester,
  BisectState? state, {
  void Function(String sha)? onJumpToCommit,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bisectStateProvider('/r').overrideWith((ref) async => state)],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BisectBar(
            repoPath: '/r',
            onJumpToCommit: onJumpToCommit ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no active bisect renders nothing', (tester) async {
    await _pump(tester, null);
    expect(find.byType(BisectBar), findsOneWidget);
    expect(find.text('Good'), findsNothing);
  });

  testWidgets(
    'no marks yet shows the bare-start message and reset, no counts',
    (tester) async {
      await _pump(tester, _state(marks: const []));
      expect(
        find.text('Bisecting. Mark a bad commit to begin.'),
        findsOneWidget,
      );
      expect(find.text('Reset bisect'), findsOneWidget);
      expect(find.text('Good'), findsNothing);
      expect(find.text('Bad'), findsNothing);
      // The defensive guard: a -1 sentinel must never reach the screen.
      expect(find.textContaining('-1'), findsNothing);
    },
  );

  testWidgets(
    'a good-only mark (no bad yet) still shows the bare-start message, '
    'not testing/verdict UI',
    (tester) async {
      await _pump(
        tester,
        _state(marks: const [BisectMark('bbb2222', BisectKind.good)]),
      );
      expect(
        find.text('Bisecting. Mark a bad commit to begin.'),
        findsOneWidget,
      );
      expect(find.textContaining('Testing'), findsNothing);
      expect(find.text('Good'), findsNothing);
      expect(find.text('Bad'), findsNothing);
      expect(find.text('Skip'), findsNothing);
    },
  );

  testWidgets('awaiting good shows guidance and reset only', (tester) async {
    await _pump(
      tester,
      _state(marks: const [BisectMark('aaa1111', BisectKind.bad)]),
    );
    expect(
      find.text('Bisecting. Mark a commit you know is good.'),
      findsOneWidget,
    );
    expect(find.text('Reset bisect'), findsOneWidget);
    expect(find.text('Good'), findsNothing);
    expect(find.text('Bad'), findsNothing);
    expect(find.textContaining('-1'), findsNothing);
  });

  testWidgets('running shows counts, testing sha and verdict buttons', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        marks: const [
          BisectMark('aaa1111', BisectKind.bad),
          BisectMark('bbb2222', BisectKind.good),
        ],
        left: 12,
        steps: 4,
      ),
    );
    expect(find.text('12 revisions left'), findsOneWidget);
    expect(find.text('about 4 steps'), findsOneWidget);
    expect(find.text('Testing head111'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Bad'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Reset bisect'), findsOneWidget);
  });

  testWidgets('one revision left reads in singular', (tester) async {
    await _pump(
      tester,
      _state(
        marks: const [
          BisectMark('aaa1111', BisectKind.bad),
          BisectMark('bbb2222', BisectKind.good),
        ],
        left: 1,
        steps: 1,
      ),
    );
    expect(find.text('1 revision left'), findsOneWidget);
    expect(find.text('about 1 step'), findsOneWidget);
  });

  testWidgets(
    'running never renders a negative count even if vars are unresolved',
    (tester) async {
      await _pump(
        tester,
        _state(
          marks: const [
            BisectMark('aaa1111', BisectKind.bad),
            BisectMark('bbb2222', BisectKind.good),
          ],
        ),
      );
      expect(find.textContaining('-1'), findsNothing);
      expect(find.text('Testing head111'), findsOneWidget);
    },
  );

  testWidgets('finished shows first bad card, not verdicts', (tester) async {
    await _pump(
      tester,
      _state(
        marks: const [BisectMark('aaa1111', BisectKind.bad)],
        left: 0,
        firstBad: 'aaa1111',
      ),
    );
    expect(find.text('First bad commit'), findsOneWidget);
    expect(find.text('Jump to commit'), findsOneWidget);
    expect(find.text('Copy SHA'), findsOneWidget);
    expect(find.text('Good'), findsNothing);
    expect(find.text('Bad'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('jump to commit reports the first bad sha', (tester) async {
    String? jumped;
    await _pump(
      tester,
      _state(
        marks: const [BisectMark('aaa1111', BisectKind.bad)],
        left: 0,
        firstBad: 'aaa1111',
      ),
      onJumpToCommit: (sha) => jumped = sha,
    );
    await tester.tap(find.text('Jump to commit'));
    await tester.pumpAndSettle();
    expect(jumped, 'aaa1111');
  });

  testWidgets('running row wraps without overflow at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      _state(
        marks: const [
          BisectMark('aaa1111', BisectKind.bad),
          BisectMark('bbb2222', BisectKind.good),
        ],
        left: 12,
        steps: 4,
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
