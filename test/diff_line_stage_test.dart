import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';
import 'package:mergelio/ui/diff/line_selection.dart';

/// One hunk with three consecutive additions, so a run can be picked out of
/// the middle of it.
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
@@ -1,1 +1,4 @@
 keep
+one
+two
+three
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Records the patch instead of touching a repository.
class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  final applied = <String>[];
  final discarded = <String>[];

  @override
  Future<void> applyPatch(String patch, {bool reverse = false}) async {
    applied.add(patch);
  }

  @override
  Future<void> discardHunk(String patch) async {
    discarded.add(patch);
  }
}

void main() {
  late _RecordingActions actions;

  Future<ProviderContainer> open(WidgetTester tester) async {
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
          repoActionsProvider.overrideWith(
            (ref, path) => actions = _RecordingActions(
              ref,
              path,
              GitWriter(_FakeGit(), path),
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

  /// The gutter of the row showing [text] — the strip left of the code, which
  /// is what picks lines out.
  Offset gutterOf(WidgetTester tester, String text) {
    final row = tester.getRect(find.textContaining(text, findRichText: true));
    return Offset(row.left - 30, row.center.dy);
  }

  testWidgets('pressing a gutter picks that line out', (tester) async {
    final c = await open(tester);

    await tester.tapAt(gutterOf(tester, 'one'));
    await tester.pumpAndSettle();

    final sel = c.read(lineSelectionProvider);
    expect(sel, isNotNull);
    expect(sel!.lines.length, 1);
  });

  testWidgets('dragging down the gutter runs the selection', (tester) async {
    final c = await open(tester);

    final gesture = await tester.startGesture(
      gutterOf(tester, 'one'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(gutterOf(tester, 'three'));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(c.read(lineSelectionProvider)!.lines.length, 3);
  });

  testWidgets('shift-click extends from the line already picked', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.tapAt(gutterOf(tester, 'one'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(gutterOf(tester, 'three'));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(c.read(lineSelectionProvider)!.lines.length, 3);
  });

  testWidgets('the menu stages only the picked-out lines', (tester) async {
    final c = await open(tester);
    await tester.tapAt(gutterOf(tester, 'two'));
    await tester.pumpAndSettle();

    await tester.tapAt(gutterOf(tester, 'two'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stage selected lines'));
    await tester.pumpAndSettle();

    expect(actions.applied, hasLength(1));
    final patch = actions.applied.single;
    expect(patch, contains('+two'));
    // The neighbouring additions were not part of the run.
    expect(patch, isNot(contains('+one')));
    expect(patch, isNot(contains('+three')));
    // Staging clears the run rather than leaving it over stale indices.
    expect(c.read(lineSelectionProvider), isNull);
  });

  testWidgets('discarding a run asks first and reverses only those lines', (
    tester,
  ) async {
    await open(tester);
    await tester.tapAt(gutterOf(tester, 'two'));
    await tester.pumpAndSettle();

    await tester.tapAt(gutterOf(tester, 'two'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard selected lines'));
    await tester.pumpAndSettle();

    expect(find.text('Discard 1 line?'), findsOneWidget);
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();

    final patch = actions.discarded.single;
    expect(patch, contains('+two'));
    // The untouched additions have to travel as context: they are in the
    // working tree this patch is reversed against, and a post-image without
    // them makes git refuse the whole patch.
    expect(patch, contains(' one'));
    expect(patch, contains(' three'));
  });

  testWidgets('with nothing picked out the menu offers only Select all', (
    tester,
  ) async {
    await open(tester);

    await tester.tapAt(gutterOf(tester, 'two'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Stage selected lines'), findsNothing);
    expect(find.text('Discard selected lines'), findsNothing);
    expect(find.text('Select all'), findsOneWidget);
  });
}
