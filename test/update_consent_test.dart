import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/update_controller.dart';
import 'package:mergelio/ui/shell/update_banner.dart';

import 'helpers/update_fakes.dart';

Future<SettingsController> _pumpConsent(
  WidgetTester tester,
  AppSettings settings,
) async {
  final controller = SettingsController(InMemorySettingsRepository(), settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => controller),
        updateStatusProvider.overrideWith(
          (ref) => fakeUpdateController(const UpdateIdle()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () {
                if (ref.read(settingsProvider).updateConsent.isEmpty) {
                  showUpdateConsentDialog(context, ref);
                }
              },
              child: const Text('ask'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ask'));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('asks while the answer is unknown', (tester) async {
    await _pumpConsent(tester, const AppSettings());
    expect(find.text('Check for updates?'), findsOneWidget);
  });

  testWidgets('does not ask again once answered', (tester) async {
    await _pumpConsent(tester, const AppSettings(updateConsent: 'off'));
    expect(find.text('Check for updates?'), findsNothing);
  });

  testWidgets('records a no', (tester) async {
    final settings = await _pumpConsent(tester, const AppSettings());
    await tester.tap(find.text("Don't check"));
    await tester.pumpAndSettle();
    expect(settings.state.updateConsent, 'off');
  });

  testWidgets('records a yes', (tester) async {
    final settings = await _pumpConsent(tester, const AppSettings());
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(settings.state.updateConsent, 'on');
  });
}
