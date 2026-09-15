// Selecting a commit the loaded history does not hold yet — what a pull does,
// since it names the new HEAD before the reloaded graph lands — must not drop
// the request: the list flies to that row as soon as the commit arrives. But
// exactly once, so a sha that never loads cannot yank the view later.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/graph_selection.dart';
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

/// History long enough to scroll, optionally headed by the pulled commit.
/// [extra] tails an unrelated commit on, to make one reload differ from
/// another without touching what the view is parked on: RepoData compares by
/// value, so an identical history is no reload at all.
RepoData _history({bool withPulled = false, bool extra = false}) => RepoData(
  commits: [
    if (withPulled) _c('pulled'),
    for (var i = 0; i < 40; i++) _c('c${i.toString().padLeft(2, '0')}'),
    if (extra) _c('extra'),
  ],
);

Finder get _list => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(_list).position;

void main() {
  /// Pumps the graph over a swappable [RepoData], parked partway down the
  /// history as a reader working through older commits.
  Future<ValueNotifier<RepoData>> pumpParked(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = ValueNotifier(_history());
    addTearDown(data.dispose);
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
            body: ValueListenableBuilder<RepoData>(
              valueListenable: data,
              builder: (_, d, _) => GraphList(data: d),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _position(tester).jumpTo(600);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 600);
    return data;
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(GraphList)));

  testWidgets('the graph flies to a selected commit that arrives later', (
    tester,
  ) async {
    final data = await pumpParked(tester);

    container(tester).read(selectedCommitProvider.notifier).state = 'pulled';
    await tester.pumpAndSettle();

    // Nothing to fly to yet — the commit is not in the loaded history.
    expect(_position(tester).pixels, 600);

    data.value = _history(withPulled: true);
    await tester.pumpAndSettle();

    // The pulled commit heads the history, so the view is back at the top.
    expect(_position(tester).pixels, 0);
  });

  testWidgets('a commit that misses twice stops being chased', (tester) async {
    final data = await pumpParked(tester);

    // A sha history never holds: a stash commit, or a tip past the commit cap.
    container(tester).read(selectedCommitProvider.notifier).state = 'pulled';
    await tester.pumpAndSettle();

    // One reload that still lacks it spends the single retry.
    data.value = _history(extra: true);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 600);

    // Should it turn up during some later, unrelated refresh, the reader is
    // left where they were rather than thrown to the top.
    data.value = _history(withPulled: true);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 600);
  });
}
