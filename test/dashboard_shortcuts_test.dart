import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/search.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/global_actions.dart';
import 'package:mergelio/ui/shell/keyboard_shortcuts.dart';

/// Records every git call; a shortcut that reached the hidden repository
/// would show up here.
class _FakeGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late ProviderContainer container;
  late _FakeGit git;
  final busyLabels = <String>[];

  Future<void> pump(WidgetTester tester) async {
    git = _FakeGit();
    busyLabels.clear();
    container = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(busyProvider, (_, next) {
      if (next != null) busyLabels.add(next.label);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Consumer(
            builder: (ctx, ref, _) => KeyboardShortcuts(
              child: Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => openGlobalPalette(ctx, ref),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  WorkspaceController ws() => container.read(workspaceProvider.notifier);

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  test('shownTab is the active tab unless the dashboard covers it', () {
    final ctl = WorkspaceController();
    final a = ctl.openRepo('/r/a');
    expect(ctl.state.shownTab?.id, a.id);
    ctl.showDashboard();
    expect(ctl.state.shownTab, isNull);
    expect(ctl.state.activeTab?.id, a.id);
  });

  testWidgets('repository shortcuts do nothing behind the dashboard', (
    tester,
  ) async {
    await pump(tester);
    ws().openRepo('/r/api');
    ws().showDashboard();
    await tester.pumpAndSettle();

    await chord(tester, LogicalKeyboardKey.keyF);
    await chord(tester, LogicalKeyboardKey.backquote);
    await chord(tester, LogicalKeyboardKey.keyB);
    await chord(tester, LogicalKeyboardKey.keyZ);

    expect(container.read(searchQueryProvider), isNull);
    expect(container.read(settingsProvider).terminalOpen, isFalse);
    expect(find.byType(Dialog), findsNothing);
    expect(busyLabels, isEmpty);
    expect(git.calls, isEmpty);
  });

  testWidgets('the same shortcuts still reach a repository that is shown', (
    tester,
  ) async {
    await pump(tester);
    ws().openRepo('/r/api');
    await tester.pumpAndSettle();

    await chord(tester, LogicalKeyboardKey.keyF);
    await chord(tester, LogicalKeyboardKey.backquote);

    expect(container.read(searchQueryProvider), isNotNull);
    expect(container.read(settingsProvider).terminalOpen, isTrue);
  });

  testWidgets('on the dashboard the palette offers the repositories only', (
    tester,
  ) async {
    await pump(tester);
    final api = ws().openRepo('/r/api');
    ws().openRepo('/r/web');
    ws().showDashboard();
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Fetch'), findsNothing);
    expect(find.text('Open dashboard'), findsNothing);
    expect(find.text('Go to web'), findsOneWidget);

    await tester.tap(find.text('Go to api'));
    await tester.pumpAndSettle();
    final state = container.read(workspaceProvider);
    expect(state.dashboard, isFalse);
    expect(state.activeTabId, api.id);
    expect(git.calls, isEmpty);
  });
}
