// Branch-vs-branch comparison from the sidebar: the current branch is the left
// side, the branch that was right-clicked is the right side.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/compare_target.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    final tracking = args.any((a) => a.contains('%(HEAD)'));
    final out = switch (args.first) {
      'remote' when args.length == 1 => 'origin\n',
      'for-each-ref' when args.contains('refs/remotes') => '',
      'for-each-ref' when tracking =>
        'main\t*\t\taaa\t\n'
            'work\t\t\tbbb\t\n',
      'for-each-ref' => 'main\nwork\n',
      'rev-parse' => 'aaa\n',
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
  Future<ProviderContainer> pumpSidebar(WidgetTester tester) async {
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
          home: Scaffold(body: RepoSidebar(onCollapse: () {})),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RepoSidebar)),
    );
    container.read(workspaceProvider.notifier).openRepo('/r');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a branch row compares against the current branch', (
    tester,
  ) async {
    final c = await pumpSidebar(tester);

    await tester.tap(find.text('work'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with current'));
    await tester.pumpAndSettle();

    expect(
      c.read(compareTargetProvider),
      const CompareTarget(repoPath: '/r', from: 'main', to: 'work'),
    );
  });

  testWidgets('the current branch offers no comparison with itself', (
    tester,
  ) async {
    await pumpSidebar(tester);

    await tester.tap(find.text('main'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PopupMenuItem<void>>(
            find.widgetWithText(PopupMenuItem<void>, 'Compare with current'),
          )
          .enabled,
      isFalse,
    );
  });
}
