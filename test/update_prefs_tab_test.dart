import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/update_controller.dart';
import 'package:mergelio/ui/preferences/updates_tab.dart';

import 'helpers/update_fakes.dart';

Future<SettingsController> _pumpTab(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(updateConsent: 'off'),
  UpdateStatus status = const UpdateIdle(),
}) async {
  final controller = SettingsController(InMemorySettingsRepository(), settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => controller),
        updateStatusProvider.overrideWith(
          (ref) => fakeUpdateController(status, settings: settings),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(body: UpdatesTab()),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('the toggle writes the consent setting', (tester) async {
    final settings = await _pumpTab(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(settings.state.updateConsent, 'on');
  });

  testWidgets('the toggle turns checking back off', (tester) async {
    final settings = await _pumpTab(
      tester,
      settings: const AppSettings(updateConsent: 'on'),
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(settings.state.updateConsent, 'off');
  });

  testWidgets('a manual check that finds nothing says so', (tester) async {
    await _pumpTab(tester, status: const UpdateNone());
    expect(find.text('Mergelio is up to date'), findsOneWidget);
  });

  testWidgets('a failed check says so', (tester) async {
    await _pumpTab(tester, status: const UpdateFailed('no network'));
    expect(find.text('Could not check for updates'), findsOneWidget);
  });

  testWidgets('never checked reads as never', (tester) async {
    await _pumpTab(tester);
    expect(find.textContaining('never'), findsOneWidget);
  });
}
