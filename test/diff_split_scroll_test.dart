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

/// Serves whatever diff body the test asks for.
class _FakeGit implements GitService {
  final String body;
  _FakeGit(this.body);

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
$body''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  Future<void> open(WidgetTester tester, String body) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit(body)),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(diffSplit: true),
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
  }

  List<ScrollPosition> horizontalPositions(WidgetTester tester) => tester
      .stateList<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      )
      .map((s) => s.position)
      .toList();

  List<ScrollPosition> verticalPositions(WidgetTester tester) => tester
      .stateList<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .map((s) => s.position)
      .toList();

  // A new file: everything is an addition, so the left column holds nothing
  // but the hunk header.
  const newFile =
      '@@ -0,0 +1,3 @@\n'
      '+a line long enough to need scrolling on its own aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
      '+second\n'
      '+third\n';

  testWidgets('each column gets its own horizontal scroll', (tester) async {
    await open(tester, newFile);
    expect(horizontalPositions(tester).length, 2);
  });

  testWidgets(
    'an empty left column has nothing to scroll while the right does',
    (tester) async {
      await open(tester, newFile);
      final [left, right] = horizontalPositions(tester);

      // This is the bug being fixed: the empty side used to be sized to the
      // widest line in the file and crowded the additions out of view.
      expect(left.maxScrollExtent, 0);
      expect(right.maxScrollExtent, greaterThan(0));
    },
  );

  testWidgets('scrolling one column sideways leaves the other alone', (
    tester,
  ) async {
    await open(tester, newFile);
    final [left, right] = horizontalPositions(tester);

    right.jumpTo(80);
    await tester.pumpAndSettle();

    expect(right.pixels, 80);
    expect(left.pixels, 0);
  });

  testWidgets('the two columns still scroll vertically as one', (tester) async {
    // Enough rows that the columns actually overflow the sheet.
    final long = StringBuffer('@@ -1,40 +1,40 @@\n');
    for (var i = 1; i <= 40; i++) {
      long.writeln(i == 20 ? '-old $i' : ' line $i');
      if (i == 20) long.writeln('+new $i');
    }
    await open(tester, long.toString());

    final verticals = verticalPositions(tester);
    expect(verticals.length, 2);

    verticals.first.jumpTo(120);
    await tester.pumpAndSettle();

    expect(verticals.last.pixels, 120, reason: 'rows must stay side by side');
  });
}
