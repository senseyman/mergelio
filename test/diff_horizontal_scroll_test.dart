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

/// Serves a diff whose changed line is far wider than any sheet.
class _FakeGit implements GitService {
  final String longLine;
  _FakeGit(this.longLine);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    if (args.first == 'diff' && !args.contains('--cached')) {
      return GitResult(0, '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-old
+$longLine
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  final long = 'x' * 400;

  Widget harness() => ProviderScope(
    overrides: [
      gitServiceProvider.overrideWithValue(_FakeGit(long)),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppTokens.dark()]),
      home: const Scaffold(
        body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    ProviderScope.containerOf(
      tester.element(find.byType(DiffSheet)),
    ).read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: 'a.txt',
    );
    await tester.pumpAndSettle();
  }

  Finder horizontalScroll() => find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
  );

  // The body nests a vertical list inside the horizontal view, so the
  // scrollable has to be picked by axis rather than by ancestry.
  ScrollPosition horizontalPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      )
      .position;

  testWidgets('the diff body scrolls sideways', (tester) async {
    await open(tester);
    expect(horizontalScroll(), findsOneWidget);
  });

  testWidgets('a long line makes the content wider than the sheet', (
    tester,
  ) async {
    await open(tester);

    // There is somewhere to scroll to, which is what clipping used to deny.
    expect(horizontalPosition(tester).maxScrollExtent, greaterThan(0));
  });

  testWidgets('the gutter travels with the code', (tester) async {
    await open(tester);
    final code = tester.getTopLeft(find.text('keep')).dx;
    final gutter = tester.getTopLeft(find.text('1').first).dx;

    horizontalPosition(tester).jumpTo(120);
    await tester.pumpAndSettle();

    // Both sit in the same row, so the line number moves exactly as far as the
    // code it labels — the columns cannot drift apart.
    expect(tester.getTopLeft(find.text('keep')).dx, code - 120);
    expect(tester.getTopLeft(find.text('1').first).dx, gutter - 120);
  });

  testWidgets('a short diff still fills the sheet width', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit('new')),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
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

    expect(horizontalPosition(tester).maxScrollExtent, 0);
  });
}
