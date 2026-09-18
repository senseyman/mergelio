// The GitHub account row lives on the Credentials tab, alongside SSH keys —
// one home for how Mergelio authenticates with remotes. Nothing else wires
// ForgeAccountRow into the app, so this is the only place that proves a
// person can actually reach it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/preferences/forge_account_row.dart';
import 'package:mergelio/ui/preferences/preferences_dialog.dart';

void main() {
  testWidgets('the Credentials tab reaches the GitHub account row', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
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

    // The tab bar is scrollable and Credentials sits past the fold, so
    // bring it into view before tapping it (mirrors how the saved-theme
    // test above scrolls a long tab into view).
    await tester.dragUntilVisible(
      find.text('Credentials'),
      find.byType(TabBar),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credentials'));
    // Not pumpAndSettle: the SSH key list below the account row reads the
    // real filesystem and shows a spinner while pending, which animates
    // forever from this test's point of view and would time out settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ForgeAccountRow), findsOneWidget);
  });
}
