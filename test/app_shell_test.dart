// Proves the app shell actually keeps the forge pull-request refresh
// scheduler alive by watching its provider — not just that
// ForgeRefreshController behaves correctly once one exists (that is covered
// in forge_refresh_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge_refresh.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/shell/app_shell.dart';

void main() {
  testWidgets('building the shell constructs the forge-refresh scheduler', (
    t,
  ) async {
    var built = false;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          // No profile/repo is set up here, so the shell renders the
          // blocking first-profile screen — but the app-lifetime controllers
          // watched above that gate must still be constructed regardless of
          // which screen ends up on display.
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(updateConsent: 'off'),
            ),
          ),
          // Wraps the real controller rather than faking it, so this also
          // proves construction does not throw given the shell's actual
          // provider graph.
          forgeRefreshProvider.overrideWith((ref) {
            built = true;
            return ForgeRefreshController(ref);
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const AppShell(),
        ),
      ),
    );
    await t.pump();

    expect(
      built,
      isTrue,
      reason:
          'AppShell must watch forgeRefreshProvider to keep the auto-refresh '
          'scheduler alive for the app lifetime',
    );
  });
}
