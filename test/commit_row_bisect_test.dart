import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/graph/commit_row.dart';
import 'package:mergelio/ui/graph/graph_rail.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';

Commit _c() => Commit(
  sha: 's1',
  message: 'fix: something',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026),
);

Future<void> _pump(WidgetTester tester, {BisectKind? bisectKind}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CommitRow(
            commit: _c(),
            branchLabels: const [],
            metrics: const RailMetrics(),
            maxLane: 0,
            cols: const {},
            selected: false,
            bisectKind: bisectKind,
            onTap: () {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('a bad-marked commit shows the bad pill', (tester) async {
    await _pump(tester, bisectKind: BisectKind.bad);
    expect(find.text('bad'), findsOneWidget);
  });

  testWidgets('a good-marked commit shows the good pill', (tester) async {
    await _pump(tester, bisectKind: BisectKind.good);
    expect(find.text('good'), findsOneWidget);
  });

  testWidgets('a skipped commit shows the skip pill', (tester) async {
    await _pump(tester, bisectKind: BisectKind.skip);
    expect(find.text('skip'), findsOneWidget);
  });

  testWidgets('an unmarked commit shows no bisect pill', (tester) async {
    await _pump(tester);
    expect(find.text('bad'), findsNothing);
    expect(find.text('good'), findsNothing);
    expect(find.text('skip'), findsNothing);
  });

  // The rail tint and the text pill are two layers of one design: a hue that
  // reads at a glance and the word that carries the verdict for anyone who
  // cannot rely on hue. Two layers of one design have to agree, so they may
  // not each keep their own copy of the colour to drift apart on the next
  // theme change.
  testWidgets('the rail tint and the pill agree on every verdict', (
    tester,
  ) async {
    const labels = {
      BisectKind.good: 'good',
      BisectKind.bad: 'bad',
      BisectKind.skip: 'skip',
    };
    for (final kind in BisectKind.values) {
      await _pump(tester, bisectKind: kind);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is GraphRailPainter,
                    ),
                  )
                  .painter
              as GraphRailPainter;
      final pill = tester.widget<Text>(find.text(labels[kind]!));
      expect(painter.bisectTint, pill.style?.color, reason: '$kind');
      expect(
        painter.bisectTint,
        bisectVerdictColor(kind, AppTokens.dark()),
        reason: '$kind must come from the theme, not a second copy',
      );
    }
  });

  testWidgets('the verdict reaches the rail painter, not only the pill', (
    tester,
  ) async {
    await _pump(tester, bisectKind: BisectKind.bad);
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is GraphRailPainter,
    );
    final painter =
        tester.widget<CustomPaint>(finder).painter as GraphRailPainter;
    expect(painter.bisectTint, AppTokens.dark().danger);
  });
}
