import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

/// Serves a canned working-tree diff for a.txt; everything else is empty.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    final cached = args.contains('--cached');
    if (args.first == 'diff' && !cached) {
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

Widget _harness() => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
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
);

Future<ProviderContainer> _open(WidgetTester tester) async {
  await tester.pumpWidget(_harness());
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DiffSheet)),
  );
  container.read(diffTargetProvider.notifier).state = const DiffTarget(
    repoPath: '/r',
    path: 'a.txt',
  );
  await tester.pumpAndSettle();
  return container;
}

/// Same as [_harness] but also serves a partially-staged working file so the
/// header's Unstaged/Staged toggle has something to react to.
Widget _harnessPartial(String repoPath) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
    repoDataProvider(repoPath).overrideWith(
      (ref) async => const RepoData(
        working: [
          WorkingFile(
            path: 'p.txt',
            index: GitChange.modified,
            worktree: GitChange.modified,
          ),
        ],
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
);

void main() {
  testWidgets('renders the hunk header and staging affordances', (
    tester,
  ) async {
    await _open(tester);
    expect(find.textContaining('@@'), findsOneWidget);
    expect(find.text('Stage hunk'), findsOneWidget);
    expect(find.text('Stage file'), findsOneWidget);
  });

  testWidgets('close button clears the diff target', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(container.read(diffTargetProvider), isNull);
  });

  testWidgets('Escape closes the sheet', (tester) async {
    final container = await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(container.read(diffTargetProvider), isNull);
  });

  testWidgets('Split toggle switches the view', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.text('Split'));
    await tester.pump();
    expect(container.read(settingsProvider).diffSplit, isTrue);
  });

  testWidgets('partial file shows the side toggle and flips the target', (
    tester,
  ) async {
    // Wide enough for the header to show the toggle as buttons: the test font
    // draws every glyph a full em wide, so labels take far more room here than
    // in the app. Narrower sheets fold these controls into a menu; that path is
    // covered in diff_header_width_test.dart.
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harnessPartial('/pr'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DiffSheet)),
    );
    container.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/pr',
      path: 'p.txt',
    );
    await tester.pumpAndSettle();

    expect(find.text('Staged').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Staged').hitTestable());
    await tester.pump();
    expect(container.read(diffTargetProvider)?.staged, isTrue);
  });
}
