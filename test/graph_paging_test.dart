// Paging the graph: when history was truncated at the page limit, the list
// carries a trailing row that asks for the next page as it scrolls into view.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_data.dart';
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

RepoData _data({required bool hasMore}) => RepoData(
  commits: [_c('aaa'), _c('bbb'), _c('ccc')],
  hasMoreCommits: hasMore,
);

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required bool hasMore,
  }) async {
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
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GraphList(data: _data(hasMore: hasMore)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(GraphList)));
  }

  testWidgets('history that ends at the root shows no loading row', (
    tester,
  ) async {
    final container = await pump(tester, hasMore: false);

    expect(find.byKey(loadMoreCommitsKey), findsNothing);
    expect(container.read(commitLimitProvider('/r')), commitPageSize);
  });

  testWidgets('truncated history shows a loading row and asks for more', (
    tester,
  ) async {
    final container = await pump(tester, hasMore: true);

    expect(find.byKey(loadMoreCommitsKey), findsOneWidget);
    expect(container.read(commitLimitProvider('/r')), commitPageSize * 2);
  });

  testWidgets('the loading row asks once per page, not once per frame', (
    tester,
  ) async {
    final container = await pump(tester, hasMore: true);

    await tester.pump();
    await tester.pump();

    expect(container.read(commitLimitProvider('/r')), commitPageSize * 2);
  });

  testWidgets('each further page doubles rather than adding a page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = WorkspaceController()..openRepo('/r');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith((ref) => workspace),
          commitLimitProvider('/r').overrideWith((_) => commitPageSize * 2),
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
          home: Scaffold(body: GraphList(data: _data(hasMore: true))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GraphList)),
    );

    // A raised limit re-walks from scratch, so a constant step would make
    // reaching the end of a long history cost 2k+4k+6k+… commits walked.
    expect(container.read(commitLimitProvider('/r')), commitPageSize * 4);
  });

  testWidgets('the loading row renders with no repo tab active', (
    tester,
  ) async {
    // A tab can close while the graph still holds the last repo's data; the
    // trailing row must not be mistaken for a commit row and index past the
    // end of the list.
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          home: Scaffold(body: GraphList(data: _data(hasMore: true))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(loadMoreCommitsKey), findsOneWidget);
  });

  testWidgets('switching repos pages the newly active one', (tester) async {
    // The graph keeps its state across a tab switch, so a guard that only
    // remembers the page limit would see the second repo's identical limit as
    // already-requested and never page it.
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = WorkspaceController()..openRepo('/r');
    final other = workspace.state.visibleTabs
        .firstWhere((t) => t.path == '/r')
        .id;
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
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: GraphList(data: _data(hasMore: true))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GraphList)),
    );
    expect(container.read(commitLimitProvider('/r')), commitPageSize * 2);

    workspace.openRepo('/s');
    expect(workspace.state.activeTab?.path, '/s');
    expect(other, isNotNull);
    await tester.pumpAndSettle();

    expect(container.read(commitLimitProvider('/s')), commitPageSize * 2);
  });
}
