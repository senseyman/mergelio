import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/update_controller.dart';
import 'package:mergelio/ui/shell/update_banner.dart';

import 'helpers/update_fakes.dart';

Future<void> _pump(WidgetTester tester, UpdateStatus status) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        updateStatusProvider.overrideWith(
          (ref) => fakeUpdateController(status),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(body: UpdateBanner()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows nothing while idle', (tester) async {
    await _pump(tester, const UpdateIdle());
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.textContaining('available'), findsNothing);
  });

  testWidgets('announces a found release', (tester) async {
    await _pump(tester, foundStatus('1.5.0+16'));
    expect(find.textContaining('1.5.0'), findsOneWidget);
  });

  testWidgets('offers install once the download is verified', (tester) async {
    await _pump(tester, readyStatus('1.5.0+16'));
    expect(find.text('Install and restart'), findsOneWidget);
  });

  testWidgets('says nothing when a background check failed', (tester) async {
    await _pump(tester, const UpdateFailed('no network'));
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.textContaining('network'), findsNothing);
  });
}
