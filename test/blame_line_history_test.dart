import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/blame.dart';
import 'package:mergelio/domain/git/line_history.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/file_insight.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/insight/file_insight_dialog.dart';

void main() {
  const repo = '/r';
  const path = 'a.txt';
  const file = (repo: repo, path: path);

  late List<LineRangeKey> asked;

  setUp(() => asked = []);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          blameProvider(file).overrideWith(
            (ref) async => const [
              BlameLine(sha: 'aaaaaaa', author: 'Maria', content: 'one'),
              BlameLine(sha: 'bbbbbbb', author: 'Maria', content: 'two'),
              BlameLine(sha: 'ccccccc', author: 'Maria', content: 'three'),
            ],
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFileInsight(
                  context,
                  repoPath: repo,
                  path: path,
                  initialTab: 1,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Right-clicks the blame row showing [content] and picks Line history.
  Future<void> pickLineHistory(WidgetTester tester, String content) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(content)),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l.lhLineHistory));
    await tester.pumpAndSettle();
  }

  testWidgets('asks for the clicked line alone', (tester) async {
    await open(tester);

    await tester.tap(find.text('two'));
    await tester.pump();
    await pickLineHistory(tester, 'two');

    expect(asked, [(repo: repo, path: path, start: 2, end: 2, rev: 'HEAD')]);
  });

  testWidgets('shift-click extends the range to the second line', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('one'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('three'));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await pickLineHistory(tester, 'three');

    expect(asked, [(repo: repo, path: path, start: 1, end: 3, rev: 'HEAD')]);
  });

  testWidgets('right-clicking outside the selection moves it even with shift', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('one'));
    await tester.pump();
    // Shift extends a left-click, but a right-click opens a menu that must act
    // on the row it opened over, not on a run the user never dragged.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await pickLineHistory(tester, 'three');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(asked, [(repo: repo, path: path, start: 3, end: 3, rev: 'HEAD')]);
  });

  testWidgets('right-clicking outside the selection moves it', (tester) async {
    await open(tester);

    await tester.tap(find.text('one'));
    await tester.pump();
    await pickLineHistory(tester, 'three');

    expect(asked, [(repo: repo, path: path, start: 3, end: 3, rev: 'HEAD')]);
  });
}
