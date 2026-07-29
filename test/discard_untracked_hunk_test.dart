import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

/// An untracked file: nothing tracked to diff, so the content only shows up
/// through `git diff --no-index`, as one hunk of pure additions.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    if (args.contains('--no-index')) {
      return const GitResult(0, '''
diff --git a/a.txt b/a.txt
--- /dev/null
+++ b/a.txt
@@ -0,0 +1,3 @@
+one
+two
+three
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  final discardedFiles = <String>[];
  final discardedPatches = <String>[];

  @override
  Future<void> discardFile(WorkingFile f) async => discardedFiles.add(f.path);

  @override
  Future<void> discardHunk(String patch) async => discardedPatches.add(patch);
}

const _untracked = WorkingFile(path: 'a.txt', worktree: GitChange.untracked);

void main() {
  late _RecordingActions actions;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          repoDataProvider.overrideWith(
            (ref, path) async => const RepoData(working: [_untracked]),
          ),
          repoActionsProvider.overrideWith(
            (ref, path) => actions = _RecordingActions(
              ref,
              path,
              GitWriter(_FakeGit(), path),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
          ),
        ),
      ),
    );
    ProviderScope.containerOf(
      tester.element(find.byType(DiffSheet)),
    ).read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: 'a.txt',
    );
    await tester.pumpAndSettle();
  }

  testWidgets('discarding the hunk of an untracked file deletes the file', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Discard hunk'));
    await tester.pumpAndSettle();
    // The wording has to say what actually happens to a file git is not
    // tracking: there is no committed state to revert it to.
    expect(find.textContaining('deletes the untracked file'), findsOneWidget);
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();

    // Reversing the patch would empty the file and leave it behind, still
    // untracked — the bug this covers.
    expect(actions.discardedFiles, ['a.txt']);
    expect(actions.discardedPatches, isEmpty);
  });
}
