import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/shell/global_actions.dart';
import 'package:mergelio/ui/workspace/remote_dialog.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    final out = switch (args.first) {
      'remote' when args.length == 1 => 'origin\n',
      'rev-parse' => 'deadbeef\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  testWidgets('the command palette offers adding a remote', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
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
    expect(find.text('Add remote…'), findsOneWidget);

    await tester.tap(find.text('Add remote…'));
    await tester.pumpAndSettle();
    expect(find.byKey(remoteNameFieldKey), findsOneWidget);
  });

  testWidgets(
    'the palette Checkout command consults the worktree-collision guard',
    (tester) async {
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
            repoDataProvider('/r').overrideWith(
              (ref) async =>
                  const RepoData(branches: [Branch(name: 'feature')]),
            ),
            worktreeByBranchProvider('/r').overrideWithValue({
              'feature': const Worktree(path: '/other', branch: 'feature'),
            }),
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
      // Warm up repoDataProvider: openGlobalPalette reads it synchronously to
      // build the command list, so it must already be resolved by then.
      container.read(repoDataProvider('/r'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checkout: feature'));
      await tester.pumpAndSettle();

      // The dialog appeared instead of an immediate checkout.
      expect(find.text('Checkout anyway'), findsOneWidget);
      expect(
        git.calls.any((c) => c.isNotEmpty && c.first == 'checkout'),
        isFalse,
      );
    },
  );
}
