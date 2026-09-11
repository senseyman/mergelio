import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/global_actions.dart';

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

/// The palette runs the same pull the bottom bar does, preferences included.
Future<List<String>> _runPalettePull(
  WidgetTester tester,
  AppSettings settings,
) async {
  final git = _FakeGit();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(InMemorySettingsRepository(), settings),
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
  await tester.tap(find.text('Pull'));
  await tester.pumpAndSettle();

  return git.calls.firstWhere((c) => c.first == 'pull');
}

void main() {
  testWidgets('the palette Pull follows the rebase preference', (tester) async {
    final pull = await _runPalettePull(
      tester,
      const AppSettings(pullStrategy: 'rebase'),
    );
    expect(pull, contains('--rebase'));
    expect(pull, contains('--autostash'));
  });

  testWidgets('the palette Pull merges by default', (tester) async {
    final pull = await _runPalettePull(tester, const AppSettings());
    expect(pull, isNot(contains('--rebase')));
  });
}
