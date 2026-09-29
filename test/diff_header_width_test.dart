import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

/// Serves a small working-tree diff for every path; staged side is empty.
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
    if (args.first == 'diff' && !args.contains('--cached')) {
      return const GitResult(0, '''
diff --git a/src/some/deeply/nested/file_name.dart b/src/some/deeply/nested/file_name.dart
--- a/src/some/deeply/nested/file_name.dart
+++ b/src/some/deeply/nested/file_name.dart
@@ -1,2 +1,2 @@
 keep
-old
+new
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _path = 'src/some/deeply/nested/file_name.dart';

/// The widest header there is: a partially staged working-tree file, which
/// shows the staging-side toggle, Edit, Stage file, the view toggle, the
/// whole-file toggle and close.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required double width,
  required Locale locale,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
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
        repoDataProvider('/r').overrideWith(
          (ref) async => const RepoData(
            working: [
              WorkingFile(
                path: _path,
                index: GitChange.modified,
                worktree: GitChange.modified,
              ),
            ],
          ),
        ),
        lfsPathsProvider.overrideWith((ref, q) async => const <String>{}),
      ],
      child: MaterialApp(
        locale: locale,
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
  c.read(diffTargetProvider.notifier).state = const DiffTarget(
    repoPath: '/r',
    path: _path,
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  // 336px is the graph column at the smallest window (960) with both side
  // panels at their default widths (264 + 360).
  const widths = [336.0, 400.0, 480.0, 560.0, 640.0, 720.0, 800.0, 1000.0];
  for (final locale in const [Locale('en'), Locale('uk')]) {
    for (final w in widths) {
      testWidgets('header fits at ${w.toInt()}px (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, width: w, locale: locale);
        expect(tester.takeException(), isNull);
        expect(find.byTooltip(_l(locale).close), findsOneWidget);
      });
    }
  }

  testWidgets('a narrow header still offers every action from its menu', (
    tester,
  ) async {
    final c = await _pump(tester, width: 336, locale: const Locale('en'));
    // The row of buttons stays in the tree to be measured, but it is not
    // shown, so only what can actually be hit counts.
    expect(find.text('Stage file').hitTestable(), findsNothing);
    // The sheet's own menu comes first; hunk headers below it may have one
    // too at this width.
    await tester.tap(find.byTooltip('More actions').hitTestable().first);
    await tester.pumpAndSettle();
    Finder inMenu(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is PopupMenuItem),
      matching: find.text(label),
    );
    for (final label in [
      'Unstaged',
      'Staged',
      'Edit',
      'Stage file',
      'Inline',
      'Split',
      'Show whole file',
    ]) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }

    // Picking the other staging side from the menu works like the toggle.
    await tester.tap(inMenu('Staged'));
    await tester.pumpAndSettle();
    expect(c.read(diffTargetProvider)?.staged, isTrue);
  });

  testWidgets('a very narrow sheet still has a usable actions menu', (
    tester,
  ) async {
    // Both side panels can be dragged wide enough to squeeze the graph
    // column far below its default share of a small window.
    for (final w in const [160.0, 200.0]) {
      await _pump(tester, width: w, locale: const Locale('uk'));
      expect(tester.takeException(), isNull, reason: '$w');
      // The sheet's own menu comes first; hunk headers may have one too.
      final menu = find.byTooltip('Інші дії').first;
      expect(tester.getSize(menu).width, greaterThan(24), reason: '$w');
      expect(menu.hitTestable(), findsOneWidget, reason: '$w');
    }
  });

  testWidgets('the view toggle speaks the user\'s language', (tester) async {
    // Wide enough for the Ukrainian labels under the test font.
    await _pump(tester, width: 1600, locale: const Locale('uk'));
    final l = _l(const Locale('uk'));
    expect(find.text(l.diffViewInline).hitTestable(), findsOneWidget);
    expect(find.text(l.diffViewSplit).hitTestable(), findsOneWidget);
    expect(find.text('Inline'), findsNothing);
  });

  testWidgets('a wide header keeps its buttons inline, with no menu', (
    tester,
  ) async {
    await _pump(tester, width: 1000, locale: const Locale('en'));
    expect(find.byTooltip('More actions').hitTestable(), findsNothing);
    expect(find.text('Stage file').hitTestable(), findsOneWidget);
    expect(find.text('Edit').hitTestable(), findsOneWidget);
  });
}

AppLocalizations _l(Locale locale) => lookupAppLocalizations(locale);
