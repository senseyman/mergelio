import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/graph/commit_row.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';

Commit _c() => Commit(
  sha: 's1',
  message: 'subject',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026),
  refs: const [GitRef(kind: RefKind.local, name: 'feature')],
);

void main() {
  testWidgets('double-clicking a branch chip activates that branch', (
    tester,
  ) async {
    final activated = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CommitRow(
            commit: _c(),
            branchLabels: const ['feature'],
            showBranchLabel: true,
            metrics: const RailMetrics(),
            maxLane: 0,
            cols: const {},
            selected: false,
            onTap: () {},
            onBranchActivated: activated.add,
          ),
        ),
      ),
    );

    final chip = find.text('feature');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(activated, ['feature']);
  });
}
