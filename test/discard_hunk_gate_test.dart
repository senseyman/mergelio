import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

/// Serves the same canned one-hunk diff for both `git diff` and
/// `git diff --cached`, so a target's side alone decides the doc's kind.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    if (args.first == 'diff') {
      return const GitResult(0, '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-old line
+new line
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool staged,
}) async {
  final container = ProviderContainer(
    overrides: [
      gitServiceProvider.overrideWithValue(_FakeGit()),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(diffTargetProvider.notifier).state = DiffTarget(
    repoPath: '/r',
    path: 'a.txt',
    staged: staged,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(
          body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the Unstaged diff hunk offers Discard hunk', (tester) async {
    await _pump(tester, staged: false);
    expect(find.text('Discard hunk'), findsWidgets);
    expect(find.text('Stage hunk'), findsWidgets);
  });

  testWidgets('the Staged diff hunk hides Discard hunk', (tester) async {
    await _pump(tester, staged: true);
    expect(find.text('Discard hunk'), findsNothing);
    expect(find.text('Unstage hunk'), findsWidgets);
  });
}
