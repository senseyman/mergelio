import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Serves a canned working-tree diff for a.txt; everything else is empty.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
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
}
