import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/blame.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/file_insight.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/insight/file_insight_dialog.dart';

void main() {
  const repo = '/r';
  const path = 'a.txt';
  const file = (repo: repo, path: path, rev: null);

  /// Opens the dialog on its Blame tab with [revsFile] as the found
  /// ignore-revs file. Both providers are overridden: the real ones read the
  /// disk and run git, neither of which a widget test can do.
  Future<ProviderContainer> open(
    WidgetTester tester, {
    String? revsFile,
  }) async {
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
            ],
          ),
          blameIgnoreRevsProvider(repo).overrideWith((ref) async => revsFile),
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
    return ProviderScope.containerOf(tester.element(find.text('one')));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Blame options'));
    await tester.pumpAndSettle();
  }

  bool checked(WidgetTester tester, String label) => tester
      .widget<CheckedPopupMenuItem<VoidCallback>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(CheckedPopupMenuItem<VoidCallback>),
        ),
      )
      .checked;

  Color? iconColor(WidgetTester tester) => tester
      .widget<Icon>(
        find.descendant(
          of: find.byTooltip('Blame options'),
          matching: find.byIcon(Icons.tune),
        ),
      )
      .color;

  testWidgets('offers whitespace and moved lines, defaults checked', (
    tester,
  ) async {
    await open(tester);
    await openMenu(tester);

    expect(checked(tester, 'Ignore whitespace'), isFalse);
    expect(checked(tester, "Don't follow moved lines"), isTrue);
    expect(checked(tester, 'Follow lines moved within the file'), isFalse);
    expect(checked(tester, 'Follow lines moved from other files'), isFalse);
    expect(find.textContaining('Skip revisions'), findsNothing);
  });

  testWidgets('picking an option updates blame and lights the icon', (
    tester,
  ) async {
    final c = await open(tester);
    final plain = iconColor(tester);

    await openMenu(tester);
    await tester.tap(find.text('Follow lines moved from other files'));
    await tester.pumpAndSettle();
    expect(c.read(blameOptionsProvider).moves, BlameMoves.acrossFiles);
    expect(iconColor(tester), isNot(plain));

    await openMenu(tester);
    await tester.tap(find.text('Ignore whitespace'));
    await tester.pumpAndSettle();
    expect(c.read(blameOptionsProvider).ignoreWhitespace, isTrue);
    expect(c.read(blameOptionsProvider).moves, BlameMoves.acrossFiles);
  });

  testWidgets('a found revs file gets a toggle, on by default', (tester) async {
    final c = await open(tester, revsFile: '/r/.git-blame-ignore-revs');
    final plain = iconColor(tester);
    await openMenu(tester);

    const label = 'Skip revisions listed in .git-blame-ignore-revs';
    expect(checked(tester, label), isTrue);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(c.read(blameOptionsProvider).skipIgnoredRevs, isFalse);
    expect(iconColor(tester), isNot(plain));
  });

  testWidgets('skipping turned off with no file found leaves the icon plain', (
    tester,
  ) async {
    final c = await open(tester);
    final plain = iconColor(tester);
    c.read(blameOptionsProvider.notifier).state = const BlameOptions(
      skipIgnoredRevs: false,
    );
    await tester.pump();
    expect(iconColor(tester), plain);
  });
}
