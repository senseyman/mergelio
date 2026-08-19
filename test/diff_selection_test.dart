import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,3 +1,3 @@
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

void main() {
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    bool split = false,
  }) async {
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

  /// Copies whatever is selected and returns what landed on the clipboard.
  Future<String> copySelection(WidgetTester tester) async {
    final state = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    // The non-deprecated route to a copy runs through the context menu, which
    // a test cannot drive; this is the same code path the shortcut calls.
    // ignore: deprecated_member_use
    state.copySelection(SelectionChangedCause.keyboard);
    await tester.pump();
    return clipboard ?? '';
  }

  Future<String> selectAllAndCopy(WidgetTester tester) async {
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll();
    await tester.pump();
    return copySelection(tester);
  }

  /// Drags across [row] to select it, the way a user grabs one line.
  Future<Rect> selectLine(WidgetTester tester, Finder row) async {
    final rect = tester.getRect(row);
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(1, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(rect.center);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(rect.centerRight - const Offset(1, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();
    return rect;
  }

  testWidgets('the diff body is selectable', (tester) async {
    await open(tester);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('asking for the selection toolbar does not throw', (
    tester,
  ) async {
    await open(tester);
    final state = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );

    // SelectableRegion._showToolbar dereferences contextMenuBuilder with `!`,
    // so a null builder crashes the frame instead of suppressing the toolbar.
    state.selectAll(SelectionChangedCause.toolbar);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('copying keeps each diff line on its own line', (tester) async {
    await open(tester);
    final copied = await selectAllAndCopy(tester);

    expect(copied, contains('\n'));
    expect(
      copied.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty),
      containsAllInOrder(['keep', 'old line', 'new line']),
    );
  });

  testWidgets('copying leaves out gutter numbers and change markers', (
    tester,
  ) async {
    await open(tester);
    final copied = await selectAllAndCopy(tester);

    expect(copied, isNot(contains('@@')));
    for (final line in copied.split('\n')) {
      expect(line.startsWith('+'), isFalse, reason: line);
      expect(line.startsWith('-'), isFalse, reason: line);
    }
  });

  testWidgets('copying leaves out the hunk action buttons', (tester) async {
    await open(tester);
    // The buttons are on screen, so a naive Select All would sweep them up.
    expect(find.text('Stage hunk'), findsOneWidget);

    final copied = await selectAllAndCopy(tester);
    expect(copied, isNot(contains('Stage hunk')));
    expect(copied, isNot(contains('Discard hunk')));
  });

  /// SelectableRegion's right-click handling branches on the platform, and the
  /// desktop path is the one this app ships on. The override has to be undone
  /// inside the test body — the framework checks it before tearDown runs.
  Future<void> onDesktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('right-click offers Select all without a prior left-click', (
    tester,
  ) async {
    await onDesktop(() async {
      await open(tester);
      // The hunk header is deliberately not selectable, and Flutter's own
      // toolbar refuses to open with nothing selected — which left a first
      // right-click here doing nothing at all.
      await tester.tap(find.textContaining('@@'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Select all'), findsOneWidget);
    });
  });

  testWidgets('the right-click menu offers Select all and nothing else', (
    tester,
  ) async {
    await onDesktop(() async {
      await open(tester);
      await tester.tap(find.textContaining('@@'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Select all'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });
  });

  testWidgets('Select all from the right-click menu then copies', (
    tester,
  ) async {
    await onDesktop(() async {
      await open(tester);
      await tester.tap(find.textContaining('@@'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      final copied = await copySelection(tester);
      expect(copied, contains('new line'));
      expect(copied, contains('\n'));
    });
  });

  testWidgets('copying takes only what is selected', (tester) async {
    await onDesktop(() async {
      await open(tester);
      await selectLine(
        tester,
        find.textContaining('new line', findRichText: true).first,
      );

      final copied = await copySelection(tester);
      expect(copied.trim(), 'new line');
      expect(copied, isNot(contains('keep')));
    });
  });

  testWidgets('a drag starting in the gutter still copies just that line', (
    tester,
  ) async {
    await onDesktop(() async {
      await open(tester);
      final row = find.textContaining('new line', findRichText: true).first;
      final rect = tester.getRect(row);
      // Grabbing a line from the left margin starts the drag inside the
      // gutter, which is a disabled selection region.
      final gesture = await tester.startGesture(
        rect.centerLeft - const Offset(40, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(rect.center);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(rect.centerRight - const Offset(1, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      final copied = await copySelection(tester);
      expect(copied.trim(), 'new line');
    });
  });

  testWidgets('right-clicking away from a selection keeps it', (tester) async {
    await onDesktop(() async {
      await open(tester);
      final row = find.textContaining('new line', findRichText: true).first;
      final rect = tester.getRect(row);
      final gesture = await tester.startGesture(
        rect.centerLeft + const Offset(1, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(rect.centerRight - const Offset(1, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();

      // Right-click on the empty space below the last diff line.
      final sheet = tester.getRect(find.byType(DiffSheet));
      final rightClick = await tester.startGesture(
        Offset(sheet.center.dx, sheet.bottom - 12),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await rightClick.up();
      await tester.pumpAndSettle();

      final copied = await copySelection(tester);
      expect(copied.trim(), 'new line');
      expect(copied, isNot(contains('keep')));
    });
  });

  /// Selects everything in one split column and returns what a copy yields.
  /// Each column scrolls on its own and is therefore its own selection region,
  /// left first in the widget tree.
  Future<String> selectAllInColumn(
    WidgetTester tester, {
    required bool left,
  }) async {
    final regions = find.byType(SelectableRegion);
    expect(regions, findsNWidgets(2), reason: 'one region per split column');
    final state = tester.state<SelectableRegionState>(regions.at(left ? 0 : 1));
    state.selectAll();
    await tester.pump();
    // ignore: deprecated_member_use
    state.copySelection(SelectionChangedCause.keyboard);
    await tester.pump();
    return clipboard ?? '';
  }

  testWidgets('the new column copies only additions and context', (
    tester,
  ) async {
    await open(tester, split: true);
    final copied = await selectAllInColumn(tester, left: false);

    // Separate regions mean the old side can no longer be interleaved line by
    // line with the new one.
    expect(copied, contains('new line'));
    expect(copied, isNot(contains('old line')));
  });

  testWidgets('the old column copies only deletions and context', (
    tester,
  ) async {
    await open(tester, split: true);
    final copied = await selectAllInColumn(tester, left: true);

    expect(copied, contains('old line'));
    expect(copied, isNot(contains('new line')));
  });
}
