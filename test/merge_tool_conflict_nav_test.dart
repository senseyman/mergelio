import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/ui/merge/merge_tool.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

List<String> _filler(int n) => [for (var i = 0; i < n; i++) 'line $i'];

/// A file whose three conflicts sit far apart, so reaching the later ones
/// takes scrolling.
ConflictFile _bigFile(String path) {
  return ConflictFile(
    path: path,
    parts: [
      ContextBlock(_filler(150)),
      ConflictHunk(ours: ['a1'], theirs: ['b1'], line: 151),
      ContextBlock(_filler(150)),
      ConflictHunk(ours: ['a2'], theirs: ['b2'], line: 306),
      ContextBlock(_filler(150)),
      ConflictHunk(ours: ['a3'], theirs: ['b3'], line: 461),
      ContextBlock(_filler(150)),
    ],
  );
}

void main() {
  const viewSize = Size(1400, 600);

  Future<ProviderContainer> pumpTool(
    WidgetTester tester,
    List<ConflictFile> files, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_FakeGit())],
    );
    addTearDown(container.dispose);
    container.read(mergeSessionProvider('/r').notifier).state = MergeSession(
      branch: 'feature',
      files: files,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: MergeTool(repoPath: '/r')),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Whether the `@@ line N @@` header of a hunk is on screen.
  bool onScreen(WidgetTester tester, int line) {
    final header = find.text('@@ line $line @@');
    if (header.evaluate().isEmpty) return false;
    final rect = tester.getRect(header);
    return rect.top >= 0 && rect.bottom <= viewSize.height;
  }

  Finder next() => find.byTooltip('Next conflict (⌥↓)');
  Finder prev() => find.byTooltip('Previous conflict (⌥↑)');

  testWidgets('before any jump the bar counts the file\'s conflicts', (
    tester,
  ) async {
    await pumpTool(tester, [_bigFile('a.txt')]);

    expect(find.text('3 conflicts'), findsOneWidget);
    expect(onScreen(tester, 306), isFalse);
  });

  testWidgets('next scrolls each conflict into view and wraps', (tester) async {
    await pumpTool(tester, [_bigFile('a.txt')]);

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);
    expect(onScreen(tester, 151), isTrue);

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 2 of 3'), findsOneWidget);
    expect(onScreen(tester, 306), isTrue);

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 3 of 3'), findsOneWidget);
    expect(onScreen(tester, 461), isTrue);
    expect(onScreen(tester, 151), isFalse);

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);
    expect(onScreen(tester, 151), isTrue);
  });

  testWidgets('previous from the top goes to the last conflict', (
    tester,
  ) async {
    await pumpTool(tester, [_bigFile('a.txt')]);

    await tester.tap(prev());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 3 of 3'), findsOneWidget);
    expect(onScreen(tester, 461), isTrue);

    await tester.tap(prev());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 2 of 3'), findsOneWidget);
    expect(onScreen(tester, 306), isTrue);
  });

  testWidgets('⌥↓ and ⌥↑ step through conflicts', (tester) async {
    await pumpTool(tester, [_bigFile('a.txt')]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('Conflict 2 of 3'), findsOneWidget);
    expect(onScreen(tester, 306), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);
    expect(onScreen(tester, 151), isTrue);
  });

  testWidgets('the shortcut stays out of the hunk editor', (tester) async {
    await pumpTool(tester, [_bigFile('a.txt')]);
    await tester.tap(next());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').first);
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);
  });

  testWidgets('switching files starts the count over', (tester) async {
    await pumpTool(tester, [_bigFile('a.txt'), _bigFile('b.txt')]);

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);

    await tester.tap(find.text('b.txt'));
    await tester.pumpAndSettle();
    expect(find.text('3 conflicts'), findsOneWidget);
    expect(onScreen(tester, 151), isFalse);
  });

  testWidgets('a single conflict reads in the singular', (tester) async {
    await pumpTool(tester, [
      ConflictFile(
        path: 'a.txt',
        parts: [
          ConflictHunk(ours: ['a'], theirs: ['b'], line: 1),
        ],
      ),
    ]);

    expect(find.text('1 conflict'), findsOneWidget);
  });

  testWidgets('a whole-file conflict has no hunks to step through', (
    tester,
  ) async {
    await pumpTool(tester, [
      const ConflictFile(
        path: 'doc.txt',
        parts: [],
        kind: ConflictKind.deletedByThem,
      ),
    ]);

    expect(next(), findsNothing);
    expect(prev(), findsNothing);
  });

  testWidgets('the bar translates with the locale', (tester) async {
    await pumpTool(tester, [_bigFile('a.txt')], locale: const Locale('uk'));

    expect(find.text('3 конфлікти'), findsOneWidget);
    await tester.tap(find.byTooltip('Наступний конфлікт (⌥↓)'));
    await tester.pumpAndSettle();
    expect(find.text('Конфлікт 1 з 3'), findsOneWidget);
  });

  testWidgets('a jump reaches a conflict the list has not built yet', (
    tester,
  ) async {
    const count = 40;
    await pumpTool(tester, [
      ConflictFile(
        path: 'huge.txt',
        parts: [
          for (var h = 0; h < count; h++) ...[
            ContextBlock(_filler(120)),
            ConflictHunk(ours: ['a$h'], theirs: ['b$h'], line: 1000 + h),
          ],
          ContextBlock(_filler(120)),
        ],
      ),
    ]);
    // Far down a lazy list, the last conflict is not even built yet.
    expect(find.text('@@ line ${1000 + count - 1} @@'), findsNothing);

    await tester.tap(prev());
    await tester.pumpAndSettle();
    expect(find.text('Conflict $count of $count'), findsOneWidget);
    expect(onScreen(tester, 1000 + count - 1), isTrue);

    await tester.tap(prev());
    await tester.pumpAndSettle();
    expect(find.text('Conflict ${count - 1} of $count'), findsOneWidget);
    expect(onScreen(tester, 1000 + count - 2), isTrue);
  });

  testWidgets('scrolling by hand moves the position, and next follows it', (
    tester,
  ) async {
    await pumpTool(tester, [_bigFile('a.txt')]);
    await tester.tap(next());
    await tester.pumpAndSettle();
    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 2 of 3'), findsOneWidget);

    // Back up into the context between the first and second conflicts.
    await tester.drag(find.text('@@ line 306 @@'), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);

    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 2 of 3'), findsOneWidget);
    expect(onScreen(tester, 306), isTrue);
  });

  testWidgets('scrolling back above the first conflict clears the position', (
    tester,
  ) async {
    await pumpTool(tester, [_bigFile('a.txt')]);
    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);

    await tester.drag(find.text('@@ line 151 @@'), const Offset(0, 5000));
    await tester.pumpAndSettle();
    expect(find.text('3 conflicts'), findsOneWidget);
  });

  testWidgets('a re-read file starts the count over', (tester) async {
    final container = await pumpTool(tester, [_bigFile('a.txt')]);
    await tester.tap(next());
    await tester.pumpAndSettle();
    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 2 of 3'), findsOneWidget);

    // Same path, freshly parsed: now with fewer conflicts. Long enough that
    // the view keeps its scroll offset, so nothing but the re-parse resets.
    container.read(mergeSessionProvider('/r').notifier).state = MergeSession(
      branch: 'feature',
      files: [
        ConflictFile(
          path: 'a.txt',
          parts: [
            ContextBlock(_filler(400)),
            ConflictHunk(ours: ['a'], theirs: ['b'], line: 401),
            ContextBlock(_filler(400)),
            ConflictHunk(ours: ['c'], theirs: ['d'], line: 806),
            ContextBlock(_filler(400)),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('2 conflicts'), findsOneWidget);
  });

  testWidgets('resolving keeps the position', (tester) async {
    await pumpTool(tester, [_bigFile('a.txt')]);
    await tester.tap(next());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept').first);
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);
  });

  testWidgets('screen readers hear the position change', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTool(tester, [_bigFile('a.txt')]);
    await tester.tap(next());
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Conflict 1 of 3')),
      matchesSemantics(label: 'Conflict 1 of 3', isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('a last conflict too near the end to reach the top still '
      'counts as landed on', (tester) async {
    await pumpTool(tester, [
      ConflictFile(
        path: 'tail.txt',
        parts: [
          ContextBlock(_filler(150)),
          ConflictHunk(ours: ['a1'], theirs: ['b1'], line: 151),
          ContextBlock(_filler(150)),
          ConflictHunk(ours: ['a2'], theirs: ['b2'], line: 306),
          ContextBlock(_filler(3)),
          ConflictHunk(ours: ['a3'], theirs: ['b3'], line: 314),
        ],
      ),
    ]);

    await tester.tap(prev());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 3 of 3'), findsOneWidget);
    expect(onScreen(tester, 314), isTrue);

    // The scroll ran out with the second conflict at the top; next must not
    // treat that as where the reader is and land on the third again.
    await tester.tap(next());
    await tester.pumpAndSettle();
    expect(find.text('Conflict 1 of 3'), findsOneWidget);
    expect(onScreen(tester, 151), isTrue);
  });
}
