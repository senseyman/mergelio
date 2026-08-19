// The Preferences modal has to close from its own ✕. It is the only dialog
// with a fixed-height body, so it is the one that runs out of room first.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/preferences/preferences_dialog.dart';

void main() {
  Future<void> openPrefs(
    WidgetTester tester, {
    AppSettings initial = const AppSettings(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(InMemorySettingsRepository(), initial),
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
    expect(find.text('Preferences'), findsOneWidget);
  }

  testWidgets('the ✕ closes Preferences', (tester) async {
    await openPrefs(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Preferences'), findsNothing);
  });

  testWidgets('the ✕ closes Preferences in a short window', (tester) async {
    tester.view.physicalSize = const Size(1100, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openPrefs(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Preferences'), findsNothing);
  });

  testWidgets('the ✕ on a saved theme removes it', (tester) async {
    await openPrefs(
      tester,
      initial: const AppSettings(savedThemes: {'Midnight': '{}'}),
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    // Saved themes sit at the bottom of a long tab.
    await tester.dragUntilVisible(
      find.text('Midnight'),
      find.byType(ListView),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.text('Midnight'), findsNothing);
  });
}
