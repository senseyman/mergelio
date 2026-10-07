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
import 'package:mergelio/ui/shell/app_toolbar.dart';
import 'package:mergelio/ui/shell/shell_widgets.dart';

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, Widget child) async {
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
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  WorkspaceController ctl() => container.read(workspaceProvider.notifier);
  WorkspaceState ws() => container.read(workspaceProvider);
  final button = find.byIcon(Icons.space_dashboard_outlined);
  BarIconButton bar(WidgetTester tester) => tester.widget<BarIconButton>(
    find.ancestor(of: button, matching: find.byType(BarIconButton)),
  );

  test('hideDashboard returns to the tab underneath', () {
    final c = WorkspaceController();
    final a = c.openRepo('/r/a');
    c.showDashboard();
    c.hideDashboard();
    expect(c.state.dashboard, isFalse);
    expect(c.state.shownTab?.id, a.id);
  });

  testWidgets('the toolbar button is disabled with no repository', (
    tester,
  ) async {
    await pump(tester, const AppToolbar());
    expect(bar(tester).onPressed, isNull);
  });

  testWidgets('the toolbar button toggles the dashboard', (tester) async {
    await pump(tester, const AppToolbar());
    final a = ctl().openRepo('/r/api');
    await tester.pump();
    expect(bar(tester).active, isFalse);

    await tester.tap(button);
    await tester.pump();
    expect(ws().dashboard, isTrue);
    expect(bar(tester).active, isTrue);

    // Pressed again, it goes back to the repository it covered.
    await tester.tap(button);
    await tester.pump();
    expect(ws().dashboard, isFalse);
    expect(ws().activeTabId, a.id);
    expect(bar(tester).active, isFalse);
  });

  testWidgets('the tab strip holds repositories only', (tester) async {
    await pump(tester, const AppTabBar());
    ctl().openRepo('/r/api');
    ctl().showDashboard();
    await tester.pump();
    expect(find.text('Dashboard'), findsNothing);
    expect(button, findsNothing);

    // A repo tab still leaves the dashboard.
    await tester.tap(find.text('api'));
    await tester.pump();
    expect(ws().dashboard, isFalse);
  });

  testWidgets('the toolbar fits the smallest window', (tester) async {
    // The window's minimum width.
    tester.view.physicalSize = const Size(960, 60);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, const AppToolbar());
    ctl().openRepo('/r/api');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
