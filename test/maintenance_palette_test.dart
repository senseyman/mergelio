import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/maintenance.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/maintenance.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/global_actions.dart';
import 'package:mergelio/ui/workspace/branch_cleanup.dart';
import 'package:mergelio/ui/workspace/maintenance_panel.dart';

class _FakeGit implements GitService {
  final calls = <String>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args.join(' '));
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Opens the global palette with `/r` active and picks [command].
Future<void> _pick(WidgetTester tester, String command) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final git = _FakeGit();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
        // The real one walks the git directory on disk.
        maintenanceSizeProvider.overrideWith(
          (ref, path) async => const MaintenanceSize(
            gitDir: '/r/.git',
            disk: GitDirSize(),
            counts: CountObjects(),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
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
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Consumer)),
  );
  container.read(workspaceProvider.notifier).openRepo('/r');
  await tester.pumpAndSettle();

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // Typed rather than found by position: the list outgrows the view. The
  // query in the field matches too; the row is the InkWell.
  await tester.enterText(find.byType(TextField).last, command);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(InkWell, command));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the palette opens the maintenance panel for the active repo', (
    tester,
  ) async {
    await _pick(tester, 'Repository maintenance…');

    final panel = tester.widget<MaintenancePanel>(
      find.byType(MaintenancePanel),
    );
    expect(panel.repoPath, '/r');
    expect(find.text('Repository maintenance'), findsOneWidget);
  });

  testWidgets('the palette opens branch clean-up on its own', (tester) async {
    await _pick(tester, 'Clean up branches…');

    final list = tester.widget<BranchCleanup>(find.byType(BranchCleanup));
    expect(list.repoPath, '/r');
    expect(find.text('Clean up branches'), findsOneWidget);
    expect(find.byType(MaintenancePanel), findsNothing);
  });
}
