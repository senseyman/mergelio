// The graph while a path filter is on: only the commits that touched the file
// count as matches, and the filter says which file it is so it can be dropped.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/search.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/path_history.dart';
import 'package:mergelio/state/search.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/graph/graph_view.dart';

Commit _c(String sha) => Commit(
  sha: sha,
  message: 'msg $sha',
  author: 'Tester',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: const [],
);

final _data = RepoData(commits: [_c('aaa'), _c('bbb'), _c('ccc')]);

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    // The search bar holds a row of filters; give it a window as wide as the
    // one a graph is actually read in rather than the 800px default.
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = WorkspaceController()..openRepo('/r');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith((ref) => workspace),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          pathHistoryProvider.overrideWith(
            (ref, PathKey key) async => const {'bbb'},
          ),
          searchQueryProvider.overrideWith(
            (ref) => const CommitQuery(path: 'lib/main.dart'),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: GraphList(data: _data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(GraphList)));
  }

  testWidgets('only the commits that touched the file are matches', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('1'), findsWidgets);
    expect(find.text('No matches'), findsNothing);
  });

  testWidgets('the bar names the file being followed', (tester) async {
    await pump(tester);

    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('clearing the file filter leaves the rest of the query', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.tap(find.byKey(const ValueKey('search:clearPath')));
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider)?.path, isEmpty);
  });
}
