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

/// A working-tree diff whose lines are far wider than the sheet, so the hunk
/// header's buttons would be pushed out of view by any content-width layout.
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
      final long = 'x' * 300;
      return GitResult(0, '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-old $long
+new $long
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
  Future<void> open(WidgetTester tester, {required bool split}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              AppSettings(diffSplit: split),
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

  /// Whether [finder] is inside the sheet's visible area rather than pushed
  /// off the side by the scrollable content.
  bool onScreen(WidgetTester tester, Finder finder) {
    final sheet = tester.getRect(find.byType(DiffSheet));
    final rect = tester.getRect(finder);
    return rect.left >= sheet.left && rect.right <= sheet.right;
  }

  testWidgets('split view puts the hunk buttons in the right column', (
    tester,
  ) async {
    await open(tester, split: true);

    final middle = tester.getCenter(find.byType(DiffSheet)).dx;
    expect(tester.getCenter(find.text('Stage hunk')).dx, greaterThan(middle));
    expect(tester.getCenter(find.text('Discard hunk')).dx, greaterThan(middle));
    // The @@ marker stays on the left, where the old line numbers are.
    expect(tester.getCenter(find.textContaining('@@')).dx, lessThan(middle));
  });

  testWidgets('the hunk buttons are reachable without scrolling', (
    tester,
  ) async {
    await open(tester, split: true);

    expect(onScreen(tester, find.text('Stage hunk')), isTrue);
    expect(onScreen(tester, find.text('Discard hunk')), isTrue);
  });

  testWidgets('the hunk buttons stay put while the column scrolls', (
    tester,
  ) async {
    await open(tester, split: true);
    final before = tester.getRect(find.text('Stage hunk'));

    final right = horizontalPositions(tester).last;
    expect(right.maxScrollExtent, greaterThan(0), reason: 'has room to scroll');
    right.jumpTo(right.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('Stage hunk')), before);
    expect(onScreen(tester, find.text('Stage hunk')), isTrue);
  });

  testWidgets('inline view keeps the buttons in view too', (tester) async {
    await open(tester, split: false);
    expect(onScreen(tester, find.text('Stage hunk')), isTrue);

    final scroll = horizontalPositions(tester).single;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(onScreen(tester, find.text('Stage hunk')), isTrue);
  });
}
