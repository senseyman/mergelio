// Selecting a stash shows what it holds, not the generic details of the commit
// git stores it as.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/signatures.dart';
import 'package:mergelio/domain/git/signature.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
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

/// The working tree panel shows while an unloaded commit is read; it probes
/// git (LFS and friends), which must not reach the host's git.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

Commit _commit(String sha) => Commit(
  sha: sha,
  message: 'msg $sha',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: const [],
);

Future<void> _pump(
  WidgetTester tester, {
  required String selected,
  Commit? unloaded,
}) async {
  final workspace = WorkspaceController()..openRepo('/r');
  final container = ProviderContainer(
    overrides: [
      gitServiceProvider.overrideWithValue(_FakeGit()),
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
      commitByShaProvider.overrideWith(
        (ref, key) async => key.sha == unloaded?.sha ? unloaded : null,
      ),
      commitSignatureProvider.overrideWith(
        (ref, key) async => SignatureVerdict.unsigned,
      ),
      tagSignatureProvider.overrideWith(
        (ref, key) async => SignatureVerdict.unsigned,
      ),
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

  testWidgets('a commit beyond the loaded page still gets its details', (
    tester,
  ) async {
    // Picked from the reflog, a review or a signature check: the graph has
    // not paged that far yet.
    await _pump(tester, selected: 'old', unloaded: _commit('old'));
    expect(find.byType(CommitDetails), findsOneWidget);
    expect(find.text('msg old'), findsOneWidget);
  });

  testWidgets('a sha the repository does not have keeps the working tree', (
    tester,
  ) async {
    await _pump(tester, selected: 'gone');
    expect(find.byType(CommitDetails), findsNothing);
  });
}
