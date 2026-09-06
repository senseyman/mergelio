import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/line_history.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/file_insight.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

/// One hunk that keeps a line, drops one and adds three, so a run can be
/// picked out of either side of the change.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    final working = args.first == 'diff' && !args.contains('--cached');
    // `show` is the commit-diff path; the sheet reads it the same way.
    if (working || args.first == 'show') {
      return const GitResult(0, '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,4 @@
 keep
-dropped
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

void main() {
  late List<LineRangeKey> asked;
  late String menuLabel;

  setUpAll(() async {
    menuLabel = (await AppLocalizations.delegate.load(
      const Locale('en'),
    )).lhLineHistory;
  });

  setUp(() => asked = []);

  Future<void> open(WidgetTester tester, {String? commitSha}) async {
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
          lineHistoryProvider.overrideWith((ref, LineRangeKey key) async {
            asked.add(key);
            return <LineHistoryEntry>[];
          }),
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
    ProviderScope.containerOf(
      tester.element(find.byType(DiffSheet)),
    ).read(diffTargetProvider.notifier).state = DiffTarget(
      repoPath: '/r',
      path: 'a.txt',
      commitSha: commitSha,
    );
    await tester.pumpAndSettle();
  }

  /// The gutter of the row showing [text] — the strip that picks lines out.
  Offset gutterOf(WidgetTester tester, String text) {
    final row = tester.getRect(find.textContaining(text, findRichText: true));
    return Offset(row.left - 30, row.center.dy);
  }

  Future<void> pick(WidgetTester tester, String text) async {
    await tester.tapAt(gutterOf(tester, text));
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String text) async {
    await tester.tapAt(gutterOf(tester, text), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  testWidgets('asks for the picked line in post-image numbering', (
    tester,
  ) async {
    await open(tester);
    await pick(tester, 'two');
    await openMenu(tester, 'two');

    await tester.tap(find.text(menuLabel));
    await tester.pumpAndSettle();

    expect(asked, [(repo: '/r', path: 'a.txt', start: 3, end: 3, rev: 'HEAD')]);
  });

  testWidgets('spans a run picked across several lines', (tester) async {
    await open(tester);
    await pick(tester, 'one');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await pick(tester, 'three');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await openMenu(tester, 'three');

    await tester.tap(find.text(menuLabel));
    await tester.pumpAndSettle();

    expect(asked, [(repo: '/r', path: 'a.txt', start: 2, end: 4, rev: 'HEAD')]);
  });

  testWidgets('resolves a commit diff against that commit', (tester) async {
    await open(tester, commitSha: 'feedface');
    await pick(tester, 'two');
    await openMenu(tester, 'two');

    await tester.tap(find.text(menuLabel));
    await tester.pumpAndSettle();

    expect(asked, [
      (repo: '/r', path: 'a.txt', start: 3, end: 3, rev: 'feedface'),
    ]);
  });

  testWidgets('offers nothing to open when no run is picked', (tester) async {
    await open(tester);
    await openMenu(tester, 'two');

    expect(find.text(menuLabel), findsNothing);
  });
}
