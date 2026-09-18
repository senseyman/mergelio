import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/graph/commit_row.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';

Commit _c() => Commit(
  sha: '0d54cb5aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  message: 'fix(forge): make a connected token take effect',
  author: 'Neo',
  authorEmail: 'someone@example.test',
  date: DateTime(2026, 9, 18),
);

Future<void> _pumpAt(
  WidgetTester tester,
  double width, {
  required bool compact,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppTokens.dark()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: CommitRow(
              commit: _c(),
              branchLabels: const [],
              metrics: RailMetrics(compact: compact),
              maxLane: 0,
              cols: const {},
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Widths a real window produces: the history panel is whatever is left after
  // the sidebar and the changes panel, so it gets narrow long before the
  // window does.
  const narrow = [560.0, 500.0, 460.0, 420.0, 380.0];

  for (final compact in [true, false]) {
    final mode = compact ? 'compact' : 'two-line';

    testWidgets('a $mode row does not overflow when the panel is narrow', (
      tester,
    ) async {
      for (final width in narrow) {
        await _pumpAt(tester, width, compact: compact);
        expect(
          tester.takeException(),
          isNull,
          reason: 'a $mode row overflowed at ${width}px',
        );
      }
    });

    testWidgets('a $mode row keeps showing the commit message when narrow', (
      tester,
    ) async {
      // The message is the reason the row exists. The author, date and sha are
      // context for it, so they are what gives way when space runs out — a row
      // that renders its metadata and nothing else has lost the plot.
      for (final width in narrow) {
        await _pumpAt(tester, width, compact: compact);
        tester.takeException();
        final title = find.textContaining('fix(forge)');
        expect(title, findsOneWidget, reason: 'no message at ${width}px');
        expect(
          tester.getSize(title.first).width,
          greaterThan(0),
          reason: 'the message was squeezed to nothing at ${width}px',
        );
      }
    });
  }
}
