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
import 'package:mergelio/domain/forge/forge_server.dart';
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
  AppSettings settings = const AppSettings(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(InMemorySettingsRepository(), settings),
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
  // The account list waits on each cloud's token lookup before it settles.
  await tester.pump();
}

void main() {
  group('forge accounts', () {
    testWidgets('with nothing connected, offers to add one', (tester) async {
      await _openCredentialsTab(tester);

      expect(find.text('Forge accounts'), findsOneWidget);
      expect(find.text('Add account…'), findsOneWidget);
      expect(find.textContaining('No accounts yet'), findsOneWidget);
      expect(find.byType(ForgeAccountRow), findsNothing);
    });

    testWidgets('lists github.com once its token is on file', (tester) async {
      await _openCredentialsTab(
        tester,
        overrides: [
          forgeAccountTokenProvider.overrideWith(
            (ref, key) async => key.host == kGithubCloud.credentialHost
                ? const ForgeToken('ghp_x')
                : null,
          ),
        ],
      );

      expect(find.text('GitHub account'), findsOneWidget);
      expect(find.text('GitLab account'), findsNothing);
      expect(find.textContaining('No accounts yet'), findsNothing);
    });

    testWidgets('lists a registered server even without a token', (
      tester,
    ) async {
      await _openCredentialsTab(
        tester,
        settings: const AppSettings(forgeServers: {'ghe.corp:8443': 'github'}),
      );

      expect(find.text('GitHub Enterprise account'), findsOneWidget);
      expect(find.text('ghe.corp:8443'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Connect…'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('a cloud account cannot be removed, only disconnected', (
      tester,
    ) async {
      await _openCredentialsTab(
        tester,
        overrides: [
          forgeAccountTokenProvider.overrideWith(
            (ref, key) async => const ForgeToken('t'),
          ),
        ],
      );

      expect(find.text('GitHub account'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Replace token…'), findsWidgets);
    });

    testWidgets('Add account opens the form', (tester) async {
      await _openCredentialsTab(tester);

      await tester.ensureVisible(find.text('Add account…'));
      await tester.pump();
      await tester.tap(find.text('Add account…'));
      // Not pumpAndSettle: the SSH key list's spinner never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add forge account'), findsOneWidget);
      expect(find.byType(ForgeTokenForm), findsOneWidget);
    });
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
              (ref, key) async => key.host == kGithubCloud.credentialHost
                  ? const ForgeToken('ghp_x')
                  : null,
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
            (ref, key) async => key.host == kGitlabCloud.credentialHost
                ? const ForgeToken('glpat_x')
                : null,
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
            (ref, key) async => key.host == kGithubCloud.credentialHost
                ? const ForgeToken('ghp_x')
                : null,
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
