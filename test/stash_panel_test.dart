import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/stash.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/stash_contents.dart';
import 'package:mergelio/ui/workspace/stash_panel.dart';

const _stash = Stash(
  ref: 'stash@{1}',
  sha: 'stashsha',
  message: 'On main: wip',
);

const _contents = StashContents(
  baseSha: 'basesha1234567',
  untrackedSha: 'untrsha',
  files: [
    CommitFileChange(path: 'lib/a.dart', change: GitChange.modified),
    CommitFileChange(
      path: 'lib/new.dart',
      origPath: 'lib/old.dart',
      change: GitChange.renamed,
    ),
  ],
  untracked: ['notes.txt'],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  StashContents contents = _contents,
}) async {
  final container = ProviderContainer(
    overrides: [
      stashContentsProvider.overrideWith((ref, key) async => contents),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(filesAsTree: false),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: StashPanel(repoPath: '/repo', stash: _stash),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('shows the stash, its base, and both kinds of files', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('stash@{1}'), findsOneWidget);
    expect(find.text('On main: wip'), findsOneWidget);
    expect(find.textContaining('basesha'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('lib/old.dart → lib/new.dart'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('UNTRACKED FILES'), findsOneWidget);
  });

  testWidgets('no untracked section for a stash without them', (tester) async {
    await _pump(
      tester,
      contents: const StashContents(
        baseSha: 'b',
        files: [CommitFileChange(path: 'x', change: GitChange.modified)],
      ),
    );
    expect(find.text('UNTRACKED FILES'), findsNothing);
  });

  testWidgets('a tracked file opens the stash diff against its base', (
    tester,
  ) async {
    final c = await _pump(tester);

    await tester.tap(find.text('lib/old.dart → lib/new.dart'));
    expect(
      c.read(diffTargetProvider),
      const DiffTarget(
        repoPath: '/repo',
        path: 'lib/new.dart',
        origPath: 'lib/old.dart',
        commitSha: 'stashsha',
        baseRev: 'basesha1234567',
        fromStash: true,
      ),
    );
  });

  testWidgets('an untracked file opens the untracked snapshot', (tester) async {
    final c = await _pump(tester);

    await tester.tap(find.text('notes.txt'));
    expect(
      c.read(diffTargetProvider),
      const DiffTarget(
        repoPath: '/repo',
        path: 'notes.txt',
        commitSha: 'untrsha',
      ),
    );
  });

  testWidgets('close clears the selection', (tester) async {
    final c = await _pump(tester);
    c.read(selectedCommitProvider.notifier).state = 'stashsha';

    await tester.tap(find.byTooltip('Close'));
    expect(c.read(selectedCommitProvider), isNull);
  });

  testWidgets('offers every stash action', (tester) async {
    await _pump(tester);
    for (final label in ['Pop', 'Apply', 'Branch…', 'Drop']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byTooltip('Rename'), findsOneWidget);
  });

  testWidgets('fits the narrowest right panel', (tester) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester);
    expect(tester.takeException(), isNull);
  });
}
