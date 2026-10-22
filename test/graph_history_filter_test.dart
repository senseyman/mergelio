// The graph while the author or date filter is on: only the commits git
// reported count as matches, the date chip sets the range, and matches past
// the loaded page are offered as a way to load more history.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/search.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/content_search.dart';
import 'package:mergelio/state/history_filter.dart';
import 'package:mergelio/state/notes.dart';
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

final _commits = [_c('aaa'), _c('bbb'), _c('ccc')];

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required CommitQuery query,
    Future<Set<String>> Function(HistoryFilterKey key)? history,
    Future<Set<String>> Function(ContentKey key)? content,
    bool hasMore = false,
    double width = 1400,
    List<HistoryFilterKey>? keys,
    RepoData? data,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = WorkspaceController()..openRepo('/r');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith((ref) => workspace),
          noteIndexProvider('/r').overrideWith((ref) async => const {}),
          bisectStateProvider('/r').overrideWith((ref) => null),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          historyFilterProvider.overrideWith((ref, HistoryFilterKey key) {
            keys?.add(key);
            return history == null ? Future.value(const {'bbb'}) : history(key);
          }),
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
          home: Scaffold(
            body: GraphList(
              data:
                  data ?? RepoData(commits: _commits, hasMoreCommits: hasMore),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(GraphList)));
  }

  testWidgets('only the commits git reported for the author are matches', (
    tester,
  ) async {
    await pump(
      tester,
      query: const CommitQuery(author: 'ada'),
      history: (_) async => const {'aaa', 'ccc'},
    );

    expect(find.text('2'), findsWidgets);
    expect(find.text('No matches'), findsNothing);
  });

  testWidgets('the filter is asked for the trimmed author and the range', (
    tester,
  ) async {
    final keys = <HistoryFilterKey>[];
    await pump(
      tester,
      query: CommitQuery(author: ' ada ', since: DateTime(2026, 3, 1)),
      keys: keys,
    );

    expect(keys.last.repoPath, '/r');
    expect(keys.last.author, 'ada');
    expect(keys.last.since, DateTime(2026, 3, 1));
    expect(keys.last.noMerges, isFalse);
  });

  testWidgets('hiding merges is part of the filter git is asked for', (
    tester,
  ) async {
    final keys = <HistoryFilterKey>[];
    await pump(
      tester,
      query: const CommitQuery(author: 'ada', hideMerges: true),
      keys: keys,
    );

    expect(keys.last.noMerges, isTrue);
  });

  // A commit, fetch or rebase moves a ref; the filter has to be asked again
  // rather than keep the shas of the history it saw before.
  testWidgets('the filter is keyed by the refs of the history shown', (
    tester,
  ) async {
    final keys = <HistoryFilterKey>[];
    final data = RepoData(
      commits: _commits,
      branches: const [Branch(name: 'main', tip: 'aaa')],
    );
    await pump(
      tester,
      query: const CommitQuery(author: 'ada'),
      keys: keys,
      data: data,
    );

    expect(keys.last.stamp, historyStamp(data));
  });

  testWidgets('enter in the author field applies it without the wait', (
    tester,
  ) async {
    final container = await pump(tester, query: const CommitQuery(text: 'm'));

    await tester.enterText(find.byKey(const ValueKey('search:author')), 'ad');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(container.read(searchQueryProvider)?.author, 'ad');
  });

  testWidgets('a filter still running is not reported as no matches', (
    tester,
  ) async {
    final pending = Completer<Set<String>>();
    addTearDown(() => pending.complete(const {}));
    await pump(
      tester,
      query: const CommitQuery(author: 'ada'),
      history: (_) => pending.future,
    );

    expect(find.text('Searching…'), findsOneWidget);
    expect(find.text('No matches'), findsNothing);
  });

  testWidgets('typing an author waits for a pause before git is asked', (
    tester,
  ) async {
    final container = await pump(tester, query: const CommitQuery(text: 'm'));

    await tester.enterText(find.byKey(const ValueKey('search:author')), 'ad');
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(searchQueryProvider)?.author, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider)?.author, 'ad');
  });

  testWidgets('a preset range covers that many days, today included', (
    tester,
  ) async {
    final container = await pump(tester, query: const CommitQuery(text: 'm'));

    await tester.tap(find.byKey(const ValueKey('search:date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();

    // Seven days counting today: the range is inclusive at both ends.
    final now = DateTime.now();
    final q = container.read(searchQueryProvider)!;
    expect(q.since, DateTime(now.year, now.month, now.day - 6));
    expect(q.until, isNull);
    expect(q.text, 'm');
  });

  testWidgets('any time clears the range', (tester) async {
    final container = await pump(
      tester,
      query: CommitQuery(
        since: DateTime(2026, 1, 1),
        until: DateTime(2026, 2, 1),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('search:date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any time'));
    await tester.pumpAndSettle();

    final q = container.read(searchQueryProvider)!;
    expect(q.since, isNull);
    expect(q.until, isNull);
  });

  testWidgets('the chip names the active range', (tester) async {
    await pump(tester, query: CommitQuery(since: DateTime(2026, 3, 8)));

    expect(find.textContaining('Since'), findsOneWidget);
    expect(find.text('Date'), findsNothing);
  });

  testWidgets('matches past the loaded page offer to load more history', (
    tester,
  ) async {
    final container = await pump(
      tester,
      query: const CommitQuery(author: 'ada'),
      history: (_) async => const {'aaa', 'old1', 'old2'},
      hasMore: true,
    );

    expect(find.text('+2'), findsOneWidget);
    // Hide-tags and the free text need the commit itself, so this is a
    // ceiling and is worded as one.
    expect(
      find.byTooltip('Up to 2 more matches in older history — load more'),
      findsOneWidget,
    );

    final before = container.read(commitLimitProvider('/r'));
    await tester.tap(find.byKey(const ValueKey('search:older')));
    await tester.pump();

    expect(container.read(commitLimitProvider('/r')), before * 2);
  });

  testWidgets('a double click on older matches loads one page, not two', (
    tester,
  ) async {
    final container = await pump(
      tester,
      query: const CommitQuery(author: 'ada'),
      history: (_) async => const {'aaa', 'old1'},
      hasMore: true,
    );

    final before = container.read(commitLimitProvider('/r'));
    await tester.tap(find.byKey(const ValueKey('search:older')));
    await tester.tap(find.byKey(const ValueKey('search:older')));
    await tester.pump();

    expect(container.read(commitLimitProvider('/r')), before * 2);
  });

  testWidgets('a query change that lands while the picker is open is kept', (
    tester,
  ) async {
    final container = await pump(
      tester,
      query: CommitQuery(
        since: DateTime(2026, 3, 1),
        until: DateTime(2026, 3, 5),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('search:date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom range…'));
    await tester.pumpAndSettle();
    // A debounced author landing behind the open picker.
    final notifier = container.read(searchQueryProvider.notifier);
    notifier.state = notifier.state!.copyWith(author: 'ada');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final q = container.read(searchQueryProvider)!;
    expect(q.author, 'ada');
    expect(q.since, DateTime(2026, 3, 1));
  });

  testWidgets('nothing older is offered once the history is all loaded', (
    tester,
  ) async {
    await pump(
      tester,
      query: const CommitQuery(author: 'ada'),
      history: (_) async => const {'aaa', 'old1'},
    );

    expect(find.byKey(const ValueKey('search:older')), findsNothing);
  });

  testWidgets('older matches wait for a content filter that is still running', (
    tester,
  ) async {
    final pending = Completer<Set<String>>();
    addTearDown(() => pending.complete(const {}));
    await pump(
      tester,
      query: const CommitQuery(author: 'ada', content: 'x'),
      history: (_) async => const {'aaa', 'old1'},
      content: (_) => pending.future,
      hasMore: true,
    );

    expect(find.byKey(const ValueKey('search:older')), findsNothing);
  });

  testWidgets('older matches have to pass the content filter too', (
    tester,
  ) async {
    await pump(
      tester,
      query: const CommitQuery(author: 'ada', content: 'x'),
      history: (_) async => const {'aaa', 'old1', 'old2'},
      content: (_) async => const {'aaa', 'old2'},
      hasMore: true,
    );

    expect(find.text('+1'), findsOneWidget);
  });

  // The graph is the middle column of a window, so the bar has far less room
  // than the window. Every filter on, with a range label, must still fit. The
  // test font draws every glyph a full em wide, so these widths are far more
  // cramped than the app; the bar without these filters needs ~736px here.
  for (final width in [1440.0 - 264 - 360, 760.0]) {
    testWidgets('the bar with every filter on fits $width px', (tester) async {
      await pump(
        tester,
        query: CommitQuery(
          author: 'ada',
          content: 'x',
          since: DateTime(2026, 3, 8),
          until: DateTime(2026, 9, 30),
        ),
        history: (_) async => const {'aaa', 'old1'},
        content: (_) async => const {'aaa', 'old1'},
        hasMore: true,
        width: width,
      );

      expect(tester.takeException(), isNull);
    });
  }
}
