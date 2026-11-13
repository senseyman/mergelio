import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/split_commit.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);
  List<String> remotes = const [];
  final splits = <String>[];
  @override
  Future<List<String>> remoteBranchesContaining(String sha) async => remotes;
  @override
  Future<void> splitCommit(String sha) async => splits.add(sha);
}

void main() {
  late _RecordingActions actions;

  Future<void> pump(
    WidgetTester tester, {
    List<String> remotes = const [],
  }) async {
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
          repoActionsProvider.overrideWith((ref, path) {
            actions = _RecordingActions(ref, path, GitWriter(_FakeGit(), path))
              ..remotes = remotes;
            // An override replaces the provider's own disposal; without it
            // the refresh timer outlives the test.
            ref.onDispose(actions.dispose);
            return actions;
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    splitCommit(context, ref, repoPath: '/r', sha: 'abc123'),
                child: const Text('split'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('split'));
    await tester.pumpAndSettle();
  }

  testWidgets('a commit on no remote is split without asking', (tester) async {
    await pump(tester);
    expect(find.text('Rewrite a pushed commit?'), findsNothing);
    expect(actions.splits, ['abc123']);
  });

  testWidgets('a pushed commit asks first, naming where it is', (tester) async {
    await pump(tester, remotes: ['origin/main']);
    expect(find.text('Rewrite a pushed commit?'), findsOneWidget);
    expect(find.textContaining('origin/main'), findsOneWidget);
    expect(actions.splits, isEmpty);

    await tester.tap(find.text('Rewrite anyway'));
    await tester.pumpAndSettle();
    expect(actions.splits, ['abc123']);
  });

  testWidgets('declining the pushed warning splits nothing', (tester) async {
    await pump(tester, remotes: ['origin/main']);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(actions.splits, isEmpty);
  });
}
