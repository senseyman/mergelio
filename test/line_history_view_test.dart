import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/line_history.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/file_insight.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/insight/line_history_dialog.dart';

void main() {
  LineRangeKey keyFor(int start, int end) =>
      (repo: '/r', path: 'a.txt', start: start, end: end, rev: 'HEAD');

  LineHistoryEntry entry({
    required String sha,
    required String message,
    String path = 'a.txt',
  }) => LineHistoryEntry(
    commit: Commit(
      sha: sha,
      message: message,
      author: 'Maria',
      authorEmail: 'm@e.com',
      date: DateTime.utc(2026, 9, 6),
    ),
    path: path,
    hunks: const [
      DiffHunk(
        header: '@@ -2,1 +2,1 @@',
        oldStart: 2,
        newStart: 2,
        lines: [
          DiffLine(type: DiffLineType.del, oldNo: 2, text: 'two'),
          DiffLine(type: DiffLineType.add, newNo: 2, text: 'TWO'),
        ],
      ),
    ],
  );

  Future<ProviderContainer> open(
    WidgetTester tester,
    AsyncValue<List<LineHistoryEntry>> value, {
    int start = 2,
    int end = 2,
  }) async {
    final key = keyFor(start, end);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          lineHistoryProvider(key).overrideWith((ref) async {
            if (value is AsyncError) {
              throw (value as AsyncError).error;
            }
            return value.requireValue;
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return TextButton(
                  onPressed: () => showLineHistory(
                    context,
                    repoPath: key.repo,
                    path: key.path,
                    start: key.start,
                    end: key.end,
                    rev: key.rev,
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('lists a row per commit that touched the range', (tester) async {
    await open(
      tester,
      AsyncValue.data([
        entry(sha: 'aaaaaaaaaaaa', message: 'edit line two'),
        entry(sha: 'bbbbbbbbbbbb', message: 'add a', path: 'old.txt'),
      ]),
    );

    expect(find.text('edit line two'), findsOneWidget);
    expect(find.text('add a'), findsOneWidget);
    expect(find.text('aaaaaaa'), findsOneWidget);
    expect(find.text('bbbbbbb'), findsOneWidget);
  });

  testWidgets('shows the range diff under each commit', (tester) async {
    await open(
      tester,
      AsyncValue.data([entry(sha: 'aaaaaaaaaaaa', message: 'edit line two')]),
    );

    expect(find.text('two'), findsOneWidget);
    expect(find.text('TWO'), findsOneWidget);
  });

  testWidgets('names the file as it stood in that commit', (tester) async {
    await open(
      tester,
      AsyncValue.data([
        entry(sha: 'bbbbbbbbbbbb', message: 'add a', path: 'old.txt'),
      ]),
    );

    expect(find.text('old.txt'), findsOneWidget);
  });

  testWidgets('says so when no commit touched the range', (tester) async {
    await open(tester, const AsyncValue.data([]));

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.lhNoChanges), findsOneWidget);
  });

  testWidgets('reports a failed read', (tester) async {
    await open(tester, AsyncValue.error(StateError('boom'), StackTrace.empty));

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.lhCouldNotLoad), findsOneWidget);
  });

  testWidgets('opening a row targets that commit and closes', (tester) async {
    final container = await open(
      tester,
      AsyncValue.data([entry(sha: 'aaaaaaaaaaaa', message: 'edit line two')]),
    );

    await tester.tap(find.text('edit line two'));
    await tester.pumpAndSettle();

    final target = container.read(diffTargetProvider);
    expect(target?.commitSha, 'aaaaaaaaaaaa');
    expect(target?.path, 'a.txt');
    expect(find.text('edit line two'), findsNothing);
  });

  testWidgets('titles a single line in the singular', (tester) async {
    await open(tester, const AsyncValue.data([]), start: 2, end: 2);

    expect(find.text('a.txt \u00b7 line 2'), findsOneWidget);
  });

  testWidgets('titles a span of lines in the plural', (tester) async {
    await open(tester, const AsyncValue.data([]), start: 2, end: 4);

    expect(find.text('a.txt \u00b7 lines 2\u20134'), findsOneWidget);
  });
}
