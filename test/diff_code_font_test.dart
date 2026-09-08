import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/theme.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

/// Serves one diff whose lines carry leading indentation, so the code font is
/// the only thing deciding how wide those indents come out.
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
diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -1,3 +1,3 @@
 void main() {
-    var old = 1;
+    var fresh = 1;
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

/// Every text style the diff paints code with, gutter numbers included.
Iterable<TextStyle> _codeStyles(WidgetTester tester) sync* {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final span = w.textSpan;
    if (span is TextSpan) {
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (child is TextSpan && child.style != null) yield child.style!;
      }
    }
    final s = w.style;
    if (s?.fontFamily != null) yield s!;
  }
}

void main() {
  testWidgets('code lines render in a family that actually resolves', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DiffSheet)),
    );
    container.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: 'a.dart',
    );
    await tester.pumpAndSettle();

    final styles = _codeStyles(tester).toList();
    // 'monospace' is a fontconfig alias: it resolves on Linux and Android and
    // silently falls back to a proportional face everywhere else, which shrinks
    // every leading space and destroys the indentation.
    expect(styles.map((s) => s.fontFamily), isNot(contains('monospace')));
    expect(
      styles.where(
        (s) =>
            s.fontFamily == AppFonts.mono &&
            (s.fontFamilyFallback ?? const []).contains('Menlo'),
      ),
      isNotEmpty,
      reason: 'diff should paint code in a family the platform can resolve',
    );
  });
}
