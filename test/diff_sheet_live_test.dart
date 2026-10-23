// The open sheet follows its file as it changes on disk: no spinner over the
// diff while it is re-read, and a run of lines picked out in the old content
// is let go once the lines under it have changed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';
import 'package:mergelio/ui/diff/line_selection.dart';

/// Serves a working-tree diff of a.txt whose added line a test can change.
class _ChangingGit implements GitService {
  var added = 'new line';

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'diff' && !args.contains('--cached')) {
      return GitResult(0, '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-old line
+$added
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _target = DiffTarget(repoPath: '/r', path: 'a.txt');

/// Runs the reload the repository's own refresh runs, from outside a provider.
final _reloader = Provider.family<void Function(), String>(
  (ref, repo) =>
      () => reloadOpenWorkingTreeDiff(ref, repo),
);

void reloadOpenWorkingTreeDiffFor(ProviderContainer c, String repo) =>
    c.read(_reloader(repo))();
const _picked = DiffLineSelection(
  path: 'a.txt',
  hunkIndex: 0,
  anchor: 1,
  focus: 2,
);

void main() {
  late _ChangingGit git;

  Future<ProviderContainer> open(WidgetTester tester) async {
    git = _ChangingGit();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
          ),
        ),
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(DiffSheet)));
    c.read(diffTargetProvider.notifier).state = _target;
    await tester.pumpAndSettle();
    c.read(lineSelectionProvider.notifier).state = _picked;
    await tester.pump();
    return c;
  }

  Future<void> reload(WidgetTester tester, ProviderContainer c) async {
    reloadOpenWorkingTreeDiffFor(c, '/r');
    await tester.pumpAndSettle();
  }

  testWidgets('shows the new content once the file changes', (tester) async {
    final c = await open(tester);
    expect(find.textContaining('new line'), findsWidgets);

    git.added = 'abs';
    await reload(tester, c);

    expect(find.textContaining('abs'), findsWidgets);
    expect(find.textContaining('new line'), findsNothing);
  });

  testWidgets('keeps the old diff on screen while it is re-read', (
    tester,
  ) async {
    final c = await open(tester);

    git.added = 'abs';
    reloadOpenWorkingTreeDiffFor(c, '/r');
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('new line'), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('lets go of picked lines whose content changed', (tester) async {
    final c = await open(tester);

    git.added = 'abs';
    await reload(tester, c);

    expect(c.read(lineSelectionProvider), isNull);
  });

  testWidgets('keeps picked lines when nothing under them changed', (
    tester,
  ) async {
    final c = await open(tester);

    await reload(tester, c);

    expect(c.read(lineSelectionProvider), _picked);
  });
}
