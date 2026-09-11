// A comparison takes over the right panel: it is the user's current question,
// so it outranks whatever commit the graph has selected.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/compare_target.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/workspace/commit_details.dart';
import 'package:mergelio/ui/workspace/compare_details.dart';
import 'package:mergelio/ui/workspace/workspace_view.dart';

final _commit = Commit(
  sha: 'aaaaaaa',
  message: 'the commit',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: const [],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CompareTarget? compare,
  String? selected,
}) async {
  final workspace = WorkspaceController()..openRepo('/r');
  final container = ProviderContainer(
    overrides: [
      workspaceProvider.overrideWith((ref) => workspace),
      repoDataProvider.overrideWith(
        (ref, path) async => RepoData(commits: [_commit]),
      ),
      commitFilesProvider.overrideWith((ref, key) async => const []),
      commitSignatureProvider.overrideWith((ref, key) async => 'N'),
      compareFilesProvider.overrideWith((ref, key) async => const []),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(compareTargetProvider.notifier).state = compare;
  container.read(selectedCommitProvider.notifier).state = selected;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SizedBox(width: 400, child: RightPanel())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('an armed comparison replaces the commit details', (
    tester,
  ) async {
    await _pump(
      tester,
      compare: const CompareTarget(repoPath: '/r', from: 'main', to: 'dev'),
      selected: 'aaaaaaa',
    );

    expect(find.byType(CompareDetails), findsOneWidget);
    expect(find.byType(CommitDetails), findsNothing);
  });

  testWidgets('selecting another commit puts the comparison away', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      compare: const CompareTarget(repoPath: '/r', from: 'main', to: 'dev'),
    );
    expect(find.byType(CompareDetails), findsOneWidget);

    c.read(selectedCommitProvider.notifier).state = 'aaaaaaa';
    await tester.pumpAndSettle();

    expect(c.read(compareTargetProvider), isNull);
    expect(find.byType(CommitDetails), findsOneWidget);
  });

  testWidgets('a comparison from another repository is not shown', (
    tester,
  ) async {
    await _pump(
      tester,
      compare: const CompareTarget(repoPath: '/other', from: 'main', to: 'dev'),
      selected: 'aaaaaaa',
    );

    expect(find.byType(CompareDetails), findsNothing);
    expect(find.byType(CommitDetails), findsOneWidget);
  });

  testWidgets('without a comparison the selected commit still wins', (
    tester,
  ) async {
    await _pump(tester, selected: 'aaaaaaa');

    expect(find.byType(CompareDetails), findsNothing);
    expect(find.byType(CommitDetails), findsOneWidget);
  });
}
