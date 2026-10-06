import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/shell/app_tab_bar.dart';

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(groupStyle: 'dropdown'),
          ),
        ),
        isLinkedWorktreeProvider.overrideWith((ref, path) async => false),
        worktreeParentProvider.overrideWith((ref, path) async => null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AppTabBar()),
        ),
      ),
    );
  }

  WorkspaceController ctl() => container.read(workspaceProvider.notifier);

  testWidgets('no dashboard entry without a repository', (tester) async {
    await pump(tester);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('the dashboard entry shows it, a repo tab leaves it', (
    tester,
  ) async {
    await pump(tester);
    ctl().openRepo('/r/api');
    await tester.pump();

    await tester.tap(find.text('Dashboard'));
    await tester.pump();
    expect(container.read(workspaceProvider).dashboard, isTrue);

    await tester.tap(find.text('api'));
    await tester.pump();
    expect(container.read(workspaceProvider).dashboard, isFalse);
  });
}
