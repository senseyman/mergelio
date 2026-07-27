import 'package:flutter/gestures.dart';
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
import 'package:mergelio/ui/workspace/remote_dialog.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add(args);
    final out = switch (args.first) {
      'remote' when args.length == 1 => 'origin\n',
      'remote' when args.contains('get-url') => 'https://example.com/o.git\n',
      'for-each-ref' when args.contains('refs/heads') => 'main\t*\t\n',
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
  Future<_FakeGit> pumpSidebar(WidgetTester tester) async {
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
    return git;
  }

  testWidgets('the remotes section offers adding a remote', (tester) async {
    await pumpSidebar(tester);

    expect(find.text('Add remote…'), findsOneWidget);

    await tester.tap(find.text('Add remote…'));
    await tester.pumpAndSettle();
    expect(find.byKey(remoteNameFieldKey), findsOneWidget);
  });

  testWidgets('a remote row offers edit and remove', (tester) async {
    await pumpSidebar(tester);

    await tester.tap(find.text('origin'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Edit remote…'), findsOneWidget);
    expect(find.text('Remove remote…'), findsOneWidget);
  });
}
