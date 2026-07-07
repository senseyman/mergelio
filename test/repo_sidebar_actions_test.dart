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

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
  }) async {
    calls.add(args);
    final out = switch (args.first) {
      'for-each-ref' when args.contains('refs/heads') =>
        'main\t*\t\nfeature\t\t\n',
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
  testWidgets('double-clicking a branch checks it out', (tester) async {
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

    // The non-current branch is checkout-able via double-tap.
    final gesture = find.text('feature');
    expect(gesture, findsOneWidget);
    await tester.tap(gesture);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(gesture);
    await tester.pumpAndSettle();

    expect(
      git.calls.any((c) => c.first == 'checkout' && c.contains('feature')),
      isTrue,
    );
  });

  testWidgets('dragging a branch onto another opens the merge/rebase menu', (
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
              const AppSettings(),
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

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('feature')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(find.text('main')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('Merge «feature» into «main»'), findsOneWidget);
    expect(find.textContaining('Rebase «feature» onto «main»'), findsOneWidget);
  });
}
