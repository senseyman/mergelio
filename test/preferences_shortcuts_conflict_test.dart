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
  testWidgets('Shortcuts lists the merge tool\'s conflict stepping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
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
    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();

    final row = find.text('Previous / next conflict (merge tool)');
    await tester.dragUntilVisible(
      row,
      find.byType(ListView).last,
      const Offset(0, -80),
    );
    expect(row, findsOneWidget);
    expect(find.text('⌥↑ / ⌥↓'), findsOneWidget);
  });
}
