import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

/// Serves a single local branch `main` (current, tip `aaa`) and a remote
/// `origin/main` (tip `bbb`) that already has a local counterpart — a
/// diverged remote, the case that must confirm before resetting.
class _FakeGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add(args);
    final out = switch (args.first) {
      'for-each-ref'
          when args.contains('refs/heads') && args[1].contains('HEAD') =>
        'main\t*\t\taaa\t\n',
      'for-each-ref' when args.contains('refs/heads') => 'main\n',
      'for-each-ref' when args.contains('refs/remotes') => 'origin/main\tbbb\n',
      'remote' => 'origin\n',
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
  testWidgets('double-tapping a diverged remote row confirms before reset', (
    tester,
  ) async {
    final git = _FakeGit();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(confirmDestructive: true),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(body: RepoSidebar(onCollapse: () {})),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RepoSidebar)),
    );
    container.read(workspaceProvider.notifier).openRepo('/r');
    await tester.pumpAndSettle();

    // 'main' renders twice: the local branch row and the remote branch row
    // (grouped under its remote, below the locals) — the remote row is last.
    final row = find.text('main').last;
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Reset & switch'), findsOneWidget);

    // No reset has happened yet — it's gated behind the confirm.
    expect(git.calls.any((c) => c.contains('--hard')), isFalse);

    await tester.tap(find.text('Reset & switch'));
    await tester.pumpAndSettle();

    expect(
      git.calls.any(
        (c) =>
            c.first == 'reset' &&
            c.contains('--hard') &&
            c.contains('origin/main'),
      ),
      isTrue,
    );
  });
}
