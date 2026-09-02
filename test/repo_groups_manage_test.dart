import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/app_tab_bar.dart';

void main() {
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    required String style,
    required Widget child,
    bool confirmDestructive = false,
  }) async {
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            AppSettings(
              groupStyle: style,
              confirmDestructive: confirmDestructive,
            ),
          ),
        ),
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

  group('dropdown switcher', () {
    testWidgets('renames the active group', (tester) async {
      await pump(tester, style: 'dropdown', child: const AppTabBar());
      ctl().setActiveGroup(ctl().createGroup('Work').id);
      await tester.pump();

      await tester.tap(find.byTooltip('Repo group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename group…'));
      await tester.pumpAndSettle();

      // The prompt pre-fills with the current name so a tweak is one edit.
      expect(find.widgetWithText(TextField, 'Work'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Clients');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(ws().groups.single.name, 'Clients');
    });

    testWidgets('deletes the active group', (tester) async {
      await pump(tester, style: 'dropdown', child: const AppTabBar());
      ctl().setActiveGroup(ctl().createGroup('Work').id);
      await tester.pump();

      await tester.tap(find.byTooltip('Repo group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete group…'));
      await tester.pumpAndSettle();

      expect(ws().groups, isEmpty);
      expect(ws().activeGroupId, isNull);
    });

    testWidgets('manage entries do nothing under "All"', (tester) async {
      await pump(tester, style: 'dropdown', child: const AppTabBar());
      ctl().createGroup('Work');
      await tester.pump();

      await tester.tap(find.byTooltip('Repo group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename group…'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(ws().groups.single.name, 'Work');
    });
  });

  group('pill switcher', () {
    testWidgets('right-click renames a pill', (tester) async {
      await pump(tester, style: 'pills', child: const AppTabBar());
      ctl().createGroup('Work');
      await tester.pump();

      await tester.tap(find.text('Work'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'OSS');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(ws().groups.single.name, 'OSS');
    });

    testWidgets('delete asks for confirmation and keeps repos open', (
      tester,
    ) async {
      await pump(
        tester,
        style: 'pills',
        child: const AppTabBar(),
        confirmDestructive: true,
      );
      final g = ctl().createGroup('Work');
      final tab = ctl().openRepo('/tmp/repo-a');
      ctl().moveToGroup(tab.id, g.id);
      await tester.pump();

      await tester.tap(find.text('Work'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete group…'));
      await tester.pumpAndSettle();

      expect(find.text('Delete group?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(ws().groups, isEmpty);
      // Deleting a group must not close its repositories.
      expect(ws().tabs.single.path, '/tmp/repo-a');
      expect(ws().tabs.single.groupId, isNull);
    });

    testWidgets('cancelling the confirmation keeps the group', (tester) async {
      await pump(
        tester,
        style: 'pills',
        child: const AppTabBar(),
        confirmDestructive: true,
      );
      ctl().createGroup('Work');
      await tester.pump();

      await tester.tap(find.text('Work'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete group…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(ws().groups.single.name, 'Work');
    });
  });

  group('rail switcher', () {
    testWidgets('right-click renames a rail item', (tester) async {
      await pump(tester, style: 'rail', child: const GroupRail());
      ctl().openRepo('/tmp/repo-a');
      ctl().createGroup('Work');
      await tester.pump();

      await tester.tap(find.byTooltip('Work'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'OSS');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(ws().groups.single.name, 'OSS');
    });

    testWidgets('right-click deletes a rail item', (tester) async {
      await pump(tester, style: 'rail', child: const GroupRail());
      ctl().openRepo('/tmp/repo-a');
      ctl().setActiveGroup(ctl().createGroup('Work').id);
      await tester.pump();

      await tester.tap(find.byTooltip('Work'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete group…'));
      await tester.pumpAndSettle();

      expect(ws().groups, isEmpty);
      expect(ws().activeGroupId, isNull);
    });
  });
}
