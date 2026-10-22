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
  testWidgets('fetching notes with every fetch is off until switched on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
    final c = ProviderScope.containerOf(tester.element(find.text('open')));

    final row = find.widgetWithText(
      SwitchListTile,
      'Fetch notes with every fetch',
    );
    expect(row, findsOneWidget);
    expect(tester.widget<SwitchListTile>(row).value, isFalse);
    expect(c.read(settingsProvider).fetchNotesWithFetch, isFalse);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).fetchNotesWithFetch, isTrue);
  });
}
