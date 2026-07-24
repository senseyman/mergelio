import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/graph/commit_row.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';

Commit _c() => Commit(
  sha: 's1',
  message: 'WIP on main',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026),
);

void main() {
  testWidgets('a stash row shows the stash@{N} pill', (tester) async {
    await tester.pumpWidget(
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
            stashLabel: 'stash@{0}',
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('stash@{0}'), findsOneWidget);
  });
}
