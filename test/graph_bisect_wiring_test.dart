import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/search.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/search.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/graph/bisect_bar.dart';
import 'package:mergelio/ui/graph/commit_row.dart';
import 'package:mergelio/ui/graph/graph_view.dart';

Commit _c(String sha) => Commit(
  sha: sha,
  message: 'msg $sha',
  author: 'Tester',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: const [],
);

BisectState _running({int left = 3, int steps = 2}) => BisectState(
  marks: const [
    BisectMark('aaa', BisectKind.bad),
    BisectMark('bbb', BisectKind.good),
  ],
  terms: const BisectTerms(),
  currentSha: 'ccc11111',
  revisionsLeft: left,
  steps: steps,
  firstBad: null,
);

Future<void> _mount(
  WidgetTester tester, {
  required BisectState? bisectState,
  CommitQuery? query,
}) async {
  final workspace = WorkspaceController()..openRepo('/r');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workspaceProvider.overrideWith((ref) => workspace),
        bisectStateProvider('/r').overrideWith((ref) => bisectState),
        searchQueryProvider.overrideWith((ref) => query),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GraphList(
            data: RepoData(
              commits: assignLanes([_c('aaa'), _c('bbb')]),
              branches: const [Branch(name: 'main', current: true)],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the bisect bar stays visible while the commit search bar is open',
    (tester) async {
      await _mount(
        tester,
        bisectState: _running(left: 3, steps: 2),
        query: const CommitQuery(),
      );

      // Sanity: the search bar really did replace the header — otherwise
      // this test would not be exercising search mode at all.
      expect(find.byType(BisectBar), findsOneWidget);
      expect(find.text('3 revisions left'), findsOneWidget);
    },
  );

  testWidgets(
    'GraphList wires each row bisect verdict from bisectStateProvider, '
    'not just CommitRow in isolation',
    (tester) async {
      await _mount(
        tester,
        bisectState: _running(left: 3, steps: 2),
        query: null,
      );

      final aaaRow = tester.widget<CommitRow>(
        find.byWidgetPredicate((w) => w is CommitRow && w.commit.sha == 'aaa'),
      );
      final bbbRow = tester.widget<CommitRow>(
        find.byWidgetPredicate((w) => w is CommitRow && w.commit.sha == 'bbb'),
      );

      expect(aaaRow.bisectKind, BisectKind.bad);
      expect(bbbRow.bisectKind, BisectKind.good);
    },
  );
}
