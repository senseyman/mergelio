// Selecting a stash shows what it holds, not the generic details of the commit
// git stores it as.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/signatures.dart';
import 'package:mergelio/domain/git/signature.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/stash.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/stash_contents.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/workspace/commit_details.dart';
import 'package:mergelio/ui/workspace/stash_panel.dart';
import 'package:mergelio/ui/workspace/workspace_view.dart';

Commit _commit(String sha) => Commit(
  sha: sha,
  message: 'msg $sha',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: const [],
);

Future<void> _pump(WidgetTester tester, {required String selected}) async {
  final workspace = WorkspaceController()..openRepo('/r');
  final container = ProviderContainer(
    overrides: [
      lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
      workspaceProvider.overrideWith((ref) => workspace),
      repoDataProvider.overrideWith(
        (ref, path) async => RepoData(
          commits: [_commit('plain'), _commit('stashsha')],
          stashes: const [
            Stash(ref: 'stash@{0}', sha: 'stashsha', message: 'wip'),
          ],
        ),
      ),
      commitFilesProvider.overrideWith((ref, key) async => const []),
      commitSignatureProvider.overrideWith(
        (ref, key) async => SignatureVerdict.unsigned,
      ),
      tagSignaturesProvider.overrideWith((ref, key) async => const []),
      stashContentsProvider.overrideWith(
        (ref, key) async => const StashContents(baseSha: 'b'),
      ),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
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
}

void main() {
  testWidgets('a selected stash opens the stash panel', (tester) async {
    await _pump(tester, selected: 'stashsha');
    expect(find.byType(StashPanel), findsOneWidget);
    expect(find.byType(CommitDetails), findsNothing);
  });

  testWidgets('any other commit keeps its details', (tester) async {
    await _pump(tester, selected: 'plain');
    expect(find.byType(StashPanel), findsNothing);
    expect(find.byType(CommitDetails), findsOneWidget);
  });
}
