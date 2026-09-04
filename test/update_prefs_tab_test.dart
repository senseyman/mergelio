import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/domain/update/update_decision.dart';
import 'package:mergelio/state/update_controller.dart';
import 'package:mergelio/ui/preferences/updates_tab.dart';

import 'helpers/update_fakes.dart';

late UpdateController lastController;

Future<SettingsController> _pumpTab(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(updateConsent: 'off'),
  UpdateStatus status = const UpdateIdle(),
  bool busy = false,
  List<String>? installed,
}) async {
  final controller = SettingsController(InMemorySettingsRepository(), settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => controller),
        // The real provider wires the controller's isBusy to this, so a test
        // that fakes one without the other is testing a state the app cannot
        // actually be in.
        if (busy) busyProvider.overrideWith((ref) => const BusyState('pull')),
        updateStatusProvider.overrideWith(
          (ref) => lastController = fakeUpdateController(
            status,
            settings: settings,
            busy: busy,
            installed: installed,
          ),
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

  group('actions on the tab', () {
    testWidgets('a found release can be downloaded from here', (tester) async {
      await _pumpTab(tester, status: foundStatus('1.5.0+16'));
      expect(find.text('Download'), findsOneWidget);

      await tester.tap(find.text('Download'));
      await tester.pump();
      await tester.pump();
      expect(lastController.state, isA<UpdateReady>());
    });

    testWidgets('a ready download can be installed from here', (tester) async {
      final installed = <String>[];
      await _pumpTab(
        tester,
        status: readyStatus('1.5.0+16'),
        installed: installed,
      );
      expect(find.text('Install and restart'), findsOneWidget);

      await tester.tap(find.text('Install and restart'));
      await tester.pump();
      expect(installed, ['/tmp/app.zip']);
    });

    testWidgets('installing is refused while Git is busy', (tester) async {
      final installed = <String>[];
      await _pumpTab(
        tester,
        status: readyStatus('1.5.0+16'),
        busy: true,
        installed: installed,
      );
      expect(find.text('Install and restart'), findsNothing);
      expect(
        find.text('Waiting for the current operation to finish'),
        findsOneWidget,
      );
      expect(installed, isEmpty);
    });

    testWidgets('a release with no build here links the notes', (tester) async {
      final m = manifestFor('1.5.0+16');
      await _pumpTab(tester, status: UpdateFound(UpdateAvailable(m, null)));
      expect(find.text('Release notes'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('a download in flight shows progress', (tester) async {
      final m = manifestFor('1.5.0+16');
      await _pumpTab(
        tester,
        status: UpdateDownloading(
          UpdateAvailable(m, m.artifacts['macos-arm64']),
          0.4,
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
