// The diff sheet has to say which two revisions a comparison is between, and
// take its status letter from the comparison rather than from a single commit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/compare_target.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async => const GitResult(0, '''
diff --git a/a.txt b/a.txt
--- /dev/null
+++ b/a.txt
@@ -0,0 +1 @@
+new file
''', '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _target = CompareTarget(repoPath: '/r', from: 'main', to: 'feature');

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        compareFilesProvider.overrideWith(
          (ref, key) async => const [
            CommitFileChange(path: 'a.txt', change: GitChange.added),
          ],
        ),
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
  ProviderScope.containerOf(
    tester.element(find.byType(DiffSheet)),
  ).read(diffTargetProvider.notifier).state = _target.fileTarget(
    'a.txt',
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the header names both revisions', (tester) async {
    await _open(tester);

    expect(find.text('main → feature'), findsOneWidget);
  });

  testWidgets('the status letter comes from the comparison', (tester) async {
    await _open(tester);

    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('a comparison offers no staging actions', (tester) async {
    await _open(tester);

    expect(find.text('Stage file'), findsNothing);
    expect(find.text('Unstage file'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });
}
