import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/common/confirm.dart';

void main() {
  Future<bool?> tap(WidgetTester tester, {required bool confirmSetting}) async {
    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              AppSettings(confirmDestructive: confirmSetting),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await confirmDestructive(
                    ref,
                    context,
                    title: 'X?',
                    body: 'b',
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('setting off skips dialog and returns true', (tester) async {
    final r = await tap(tester, confirmSetting: false);
    expect(r, isTrue);
    expect(find.text('X?'), findsNothing);
  });

  testWidgets('setting on shows the confirm dialog', (tester) async {
    await tap(tester, confirmSetting: true);
    expect(find.text('X?'), findsOneWidget);
  });
}
