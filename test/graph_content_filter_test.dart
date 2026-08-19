// The graph while a content filter is on: only the commits whose diff mentions
// the string count as matches, and the bar says the pickaxe is still running
// rather than claiming there is nothing to find.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/search.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/content_search.dart';
import 'package:mergelio/state/repo_data.dart';
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
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required CommitQuery query,
    Future<Set<String>> Function(ContentKey key)? content,
    double width = 1400,
  }) async {
    // The search bar holds a row of filters; give it a window as wide as the
    // one a graph is actually read in rather than the 800px default.
    tester.view.physicalSize = Size(width, 800);
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
          contentSearchProvider.overrideWith(
            (ref, ContentKey key) =>
                content == null ? Future.value(const {'bbb'}) : content(key),
          ),
          searchQueryProvider.overrideWith((ref) => query),
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

  testWidgets('only the commits the pickaxe reported are matches', (
    tester,
  ) async {
    await pump(tester, query: const CommitQuery(content: 'parseUrl'));

    expect(find.text('1'), findsWidgets);
    expect(find.text('No matches'), findsNothing);
  });

  testWidgets('a search still running is not reported as no matches', (
    tester,
  ) async {
    final pending = Completer<Set<String>>();
    addTearDown(() => pending.complete(const {}));
    await pump(
      tester,
      query: const CommitQuery(content: 'parseUrl'),
      content: (_) => pending.future,
    );

    expect(find.text('Searching…'), findsOneWidget);
    expect(find.text('No matches'), findsNothing);
  });

  testWidgets('a finished search with nothing to show says so', (tester) async {
    await pump(
      tester,
      query: const CommitQuery(content: 'parseUrl'),
      content: (_) async => const {},
    );

    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('the regex toggle switches the query to diff-text mode', (
    tester,
  ) async {
    final container = await pump(
      tester,
      query: const CommitQuery(content: 'parseUrl'),
    );

    await tester.tap(find.text('.*'));
    await tester.pumpAndSettle();

    expect(
      container.read(searchQueryProvider)?.contentMode,
      ContentSearchMode.diffText,
    );
  });

  testWidgets('typing waits for a pause before the pickaxe is run', (
    tester,
  ) async {
    final container = await pump(tester, query: const CommitQuery(text: 'msg'));

    await tester.enterText(find.byKey(const ValueKey('search:content')), 'par');
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(searchQueryProvider)?.content, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider)?.content, 'par');
  });

  testWidgets('submitting the content field searches without the wait', (
    tester,
  ) async {
    final container = await pump(tester, query: const CommitQuery(text: 'msg'));

    await tester.enterText(find.byKey(const ValueKey('search:content')), 'par');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(container.read(searchQueryProvider)?.content, 'par');
  });

  testWidgets('the pickaxe is not run while no content is being searched for', (
    tester,
  ) async {
    final keys = <ContentKey>[];
    await pump(
      tester,
      query: const CommitQuery(text: 'msg'),
      content: (key) async {
        keys.add(key);
        return const {};
      },
    );

    expect(keys, isEmpty);
    expect(find.text('3'), findsWidgets);
  });

  // The graph is the middle column between two resizable panels, so its width
  // is the window minus both of them — on a laptop that is far less than the
  // whole screen. A filter row that only fits on a wide monitor would greet
  // most users with overflow stripes.
  testWidgets('the bar fits the graph panel of a laptop-sized window', (
    tester,
  ) async {
    // A 1440-wide window less the two default side panels. Anything the filter
    // row cannot fit here greets most users with overflow stripes.
    await pump(
      tester,
      query: const CommitQuery(content: 'parseUrl'),
      width: 1440 - 264 - 360,
    );
  });
}
