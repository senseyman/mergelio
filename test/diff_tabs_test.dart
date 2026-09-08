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
import 'package:mergelio/ui/diff/diff_selection.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

/// Serves a tab-indented hunk, the way gofmt would write one.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    if (args.first == 'diff' && !args.contains('--cached')) {
      return const GitResult(0, '''
diff --git a/a.go b/a.go
--- a/a.go
+++ b/a.go
@@ -1,3 +1,3 @@
 func main() {
-\tprintln("old")
+\tprintln("new")
 }
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

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(_harness());
  ProviderScope.containerOf(
    tester.element(find.byType(DiffSheet)),
  ).read(diffTargetProvider.notifier).state = const DiffTarget(
    repoPath: '/r',
    path: 'a.go',
  );
  await tester.pumpAndSettle();
}

/// The text the diff actually paints, row by row.
List<String> _painted(WidgetTester tester) => [
  for (final w in tester.widgetList<Text>(find.byType(Text)))
    if (w.textSpan != null) w.textSpan!.toPlainText(),
];

void main() {
  testWidgets('tab-indented code paints at its real indentation', (
    tester,
  ) async {
    await _open(tester);

    final code = _painted(tester).where((s) => s.contains('println')).toList();
    expect(code, isNotEmpty, reason: 'the hunk should be on screen');
    for (final line in code) {
      // Flutter shapes a tab as one narrow glyph, so leaving it in place
      // collapses the indentation to a single column.
      expect(line, isNot(contains('\t')));
      expect(line, startsWith('    println'));
    }
  });

  testWidgets('copying a whole row still yields the original tabs', (
    tester,
  ) async {
    await _open(tester);

    final rows = tester
        .widgetList<DiffSelectableLine>(find.byType(DiffSelectableLine))
        .where((w) => w.rawText.contains('println'))
        .toList();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      // Pasting a Go line back into a Go file has to bring its tabs with it.
      expect(row.rawText, startsWith('\tprintln'));
      expect(row.text, startsWith('    println'));
    }
  });
}
