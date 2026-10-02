// A stash read against its base offers each hunk to the working tree; a plain
// comparison offers nothing to apply.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
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
    String? stdin,
  }) async => const GitResult(0, '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-old
+new
''', '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

Future<void> _open(WidgetTester tester, {required bool fromStash}) async {
  tester.view.physicalSize = const Size(1200, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  ProviderScope.containerOf(tester.element(find.byType(DiffSheet)))
      .read(diffTargetProvider.notifier)
      .state = DiffTarget(
    repoPath: '/r',
    path: 'a.txt',
    commitSha: 'a' * 40,
    baseRev: 'b' * 40,
    fromStash: fromStash,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a stash hunk can be applied, not staged or discarded', (
    tester,
  ) async {
    await _open(tester, fromStash: true);

    expect(find.text('Apply hunk'), findsOneWidget);
    expect(find.text('Stage hunk'), findsNothing);
    expect(find.text('Discard hunk'), findsNothing);
  });

  testWidgets('a plain comparison has no hunk actions', (tester) async {
    await _open(tester, fromStash: false);

    expect(find.text('Apply hunk'), findsNothing);
    expect(find.text('Stage hunk'), findsNothing);
  });
}
