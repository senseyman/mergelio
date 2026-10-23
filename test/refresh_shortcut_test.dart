// ⌘R / Ctrl+R and the palette re-read the shown repository on demand.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/global_actions.dart';
import 'package:mergelio/ui/shell/keyboard_shortcuts.dart';

import 'support/refresh_counter.dart';

void main() {
  late Map<String, int> refreshes;
  late WorkspaceController workspace;

  /// [child] stands in for whatever has focus under the shortcuts.
  Future<void> pump(WidgetTester tester, {Widget? child}) async {
    refreshes = {};
    workspace = WorkspaceController()..openRepo('/nowhere/r');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(SilentGit()),
          workspaceProvider.overrideWith((ref) => workspace),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          countRefreshes(refreshes),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Consumer(
            builder: (ctx, ref, _) => KeyboardShortcuts(
              child: Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => openGlobalPalette(ctx, ref),
                      child: const Text('open'),
                    ),
                    ?child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey modifier) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('⌘R re-reads the shown repository', (tester) async {
    await pump(tester);

    await press(tester, LogicalKeyboardKey.metaLeft);

    expect(refreshes, {'/nowhere/r': 1});
  });

  testWidgets('Ctrl+R re-reads the shown repository', (tester) async {
    await pump(tester);

    await press(tester, LogicalKeyboardKey.controlLeft);

    expect(refreshes, {'/nowhere/r': 1});
  });

  testWidgets('over the dashboard it re-reads nothing', (tester) async {
    await pump(tester);
    workspace.showDashboard();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.metaLeft);

    expect(refreshes, isEmpty);
  });

  testWidgets('a focused view that takes the key keeps it', (tester) async {
    // The terminal answers Ctrl+R itself — it is the shell's history search.
    final node = FocusNode();
    addTearDown(node.dispose);
    await pump(
      tester,
      child: Focus(
        focusNode: node,
        onKeyEvent: (_, e) =>
            e.logicalKey == LogicalKeyboardKey.keyR &&
                HardwareKeyboard.instance.isControlPressed
            ? KeyEventResult.handled
            : KeyEventResult.ignored,
        child: const SizedBox(),
      ),
    );
    // Clicked into, as the terminal would be.
    node.requestFocus();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.controlLeft);

    expect(refreshes, isEmpty);
  });

  testWidgets('the palette offers Refresh', (tester) async {
    await pump(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(refreshes, {'/nowhere/r': 1});
  });
}
