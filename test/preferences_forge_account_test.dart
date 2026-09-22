// The GitHub and GitLab account rows live on the Credentials tab, alongside
// SSH keys — one home for how Mergelio authenticates with remotes. Nothing
// else wires ForgeAccountRow into the app, so this is the only place that
// proves a person can actually reach either one.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/preferences/forge_account_row.dart';
import 'package:mergelio/ui/preferences/preferences_dialog.dart';

/// The Credentials tab's own list, identified by its padding rather than by
/// type alone — a plain `find.byType(ListView)` is ambiguous once the
/// General tab's ListView survives underneath as a PageView neighbor.
final _credentialsListView = find.byWidgetPredicate(
  (w) => w is ListView && w.padding == const EdgeInsets.all(14),
);

/// Opens Preferences and brings the Credentials tab into view, the shape
/// every test in this file needs before it can see either account row.
Future<void> _openCredentialsTab(
  WidgetTester tester, {
  List<Override> overrides = const [],
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
        // ForgeAccountRow watches forgeAccountTokenProvider unconditionally
        // (it no longer depends on a repository being open), and that
        // provider shells out to the real git credential helper unless
        // overridden — exactly the file I/O widget tests cannot do, and on
        // some machines a real osxkeychain prompt.
        forgeAccountTokenProvider.overrideWith((ref, key) async => null),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPreferencesDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  // The tab bar is scrollable and Credentials sits past the fold, so bring
  // it into view before tapping it.
  await tester.dragUntilVisible(
    find.text('Credentials'),
    find.byType(TabBar),
    const Offset(-200, 0),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Credentials'));
  // Not pumpAndSettle: the SSH key list below the account rows reads the
  // real filesystem and shows a spinner while pending, which animates
  // forever from this test's point of view and would time out settling.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  // The dialog's body is a fixed height and both account rows together, plus
  // the refresh row they gate, overflow it — dragged from the GitHub row's
  // own title (always on screen, unlike a plain ListView finder, which is
  // ambiguous: the General tab's ListView survives as a PageView neighbor).
  // One deliberate drag, not an incremental search: a sliver only ever
  // builds what the current viewport needs, so a single jump reveals the
  // rest in one pass instead of needing a target that already exists.
  await tester.drag(find.text('GitHub account'), const Offset(0, -500));
  await tester.pump();
}

void main() {
  testWidgets('the Credentials tab reaches both account rows', (tester) async {
    await _openCredentialsTab(tester);
    // The dialog's body is a fixed height and both rows together overflow
    // it, so the GitLab row starts outside the sliver's cache extent and is
    // not part of the widget tree until something scrolls it into range.
    await tester.dragUntilVisible(
      find.text('GitLab account'),
      _credentialsListView,
      const Offset(0, -80),
    );

    expect(find.byType(ForgeAccountRow), findsNWidgets(2));
  });

  testWidgets('preferences offers an account row per forge', (tester) async {
    await _openCredentialsTab(tester);

    expect(find.text('GitHub account'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('GitLab account'),
      _credentialsListView,
      const Offset(0, -80),
    );
    expect(find.text('GitLab account'), findsOneWidget);
  });

  group('refresh interval', () {
    testWidgets('is hidden when neither forge has a token on file', (
      tester,
    ) async {
      await _openCredentialsTab(tester);

      expect(find.text('10m'), findsNothing);
    });

    testWidgets(
      'renders exactly once, not once per row, when the github token is on '
      'file',
      (tester) async {
        await _openCredentialsTab(
          tester,
          overrides: [
            forgeAccountTokenProvider.overrideWith(
              (ref, key) async =>
                  key.host == kGithubHost ? const ForgeToken('ghp_x') : null,
            ),
          ],
        );
        // The refresh row sits below both account rows, further out than
        // the dialog's fixed-height body shows without scrolling.
        await tester.dragUntilVisible(
          find.text('10m'),
          _credentialsListView,
          const Offset(0, -80),
        );

        expect(find.text('10m'), findsOneWidget);
      },
    );

    testWidgets('shows when only the gitlab token is on file', (tester) async {
      await _openCredentialsTab(
        tester,
        overrides: [
          forgeAccountTokenProvider.overrideWith(
            (ref, key) async =>
                key.host == kGitlabHost ? const ForgeToken('glpat_x') : null,
          ),
        ],
      );
      await tester.dragUntilVisible(
        find.text('10m'),
        _credentialsListView,
        const Offset(0, -80),
      );

      expect(find.text('10m'), findsOneWidget);
    });

    testWidgets('choosing an interval updates the shared setting', (
      tester,
    ) async {
      late SettingsController ctl;
      await _openCredentialsTab(
        tester,
        overrides: [
          forgeAccountTokenProvider.overrideWith(
            (ref, key) async =>
                key.host == kGithubHost ? const ForgeToken('ghp_x') : null,
          ),
          settingsProvider.overrideWith(
            (ref) => ctl = SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
      );
      await tester.dragUntilVisible(
        find.text('10m'),
        _credentialsListView,
        const Offset(0, -80),
      );

      expect(find.text('10m'), findsOneWidget);

      // '10m' is enough to prove the row rendered, but ensureVisible aligns
      // to whatever it was asked to reveal — '5m' sits earlier in the same
      // row and can still be clipped at the very edge of the viewport, which
      // is exactly where a tap's hit test misses. Settle once more before
      // tapping: dragUntilVisible stops as soon as the finder resolves, not
      // once the scroll's own frame has finished laying out.
      await tester.dragUntilVisible(
        find.text('5m'),
        _credentialsListView,
        const Offset(0, -20),
      );
      await tester.pump();
      await tester.tap(find.text('5m'));
      await tester.pump();

      expect(ctl.state.forgeRefreshIntervalSeconds, 300);
    });
  });
}
