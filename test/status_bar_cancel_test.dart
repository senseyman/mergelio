// The status bar is where a running git operation becomes visible and, when it
// stalls on a remote that has stopped answering, where it can be given up on.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/shell/app_status_bar.dart';

void main() {
  Future<ProviderContainer> pumpBar(WidgetTester tester) async {
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
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: AppStatusBar()),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(AppStatusBar)));
  }

  testWidgets('an idle app names no operation', (tester) async {
    await pumpBar(tester);
    await tester.pump();

    expect(find.byKey(runningOpLabelKey), findsNothing);
    expect(find.byKey(cancelRunningOpKey), findsNothing);
  });

  testWidgets('a running fetch is named and can be abandoned', (tester) async {
    final c = await pumpBar(tester);
    var cancelled = false;
    c.read(fetchBusyProvider.notifier).state = BusyState.network(
      'Fetch',
      onCancel: () => cancelled = true,
    );
    await tester.pump();

    expect(find.text('Fetch'), findsOneWidget);

    await tester.tap(find.byKey(cancelRunningOpKey));
    expect(cancelled, isTrue);
  });

  testWidgets('the repository lane is named ahead of a background fetch', (
    tester,
  ) async {
    final c = await pumpBar(tester);
    c.read(fetchBusyProvider.notifier).state = const BusyState.network('Fetch');
    c.read(busyProvider.notifier).state = const BusyState('Push');
    await tester.pump();

    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Fetch'), findsNothing);
  });

  testWidgets('an operation with nothing to abandon offers no cancel', (
    tester,
  ) async {
    final c = await pumpBar(tester);
    c.read(busyProvider.notifier).state = const BusyState('Rebase');
    await tester.pump();

    expect(find.text('Rebase'), findsOneWidget);
    expect(find.byKey(cancelRunningOpKey), findsNothing);
  });
}
