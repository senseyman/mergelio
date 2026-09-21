import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    final out = switch (args.first) {
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

/// Pumps [RepoSidebar] with the active repo open and the forge providers
/// overridden — following the same setup `repo_sidebar_actions_test.dart`
/// uses to avoid the sidebar's own filesystem reads, plus the forge overrides
/// `forge_section_test.dart` uses so nothing here spawns a real git process
/// or network call to resolve `origin`.
Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
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
        worktreeByBranchProvider('/r').overrideWithValue(const {}),
        repoDataProvider('/r').overrideWith((ref) async => const RepoData()),
        ...overrides,
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
}

void main() {
  testWidgets('shows the pull request section for a repository on a forge', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => const ForgePanel(),
        ),
        issuePanelProvider.overrideWith((ref, path) async => const []),
      ],
    );

    // SidebarSection headers render their label uppercased.
    expect(find.text('PULL REQUESTS'), findsOneWidget);
    expect(find.text('ISSUES'), findsOneWidget);
  });

  testWidgets('hides the pull request section for a repository off any forge', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => null),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => const ForgePanel(),
        ),
        issuePanelProvider.overrideWith((ref, path) async => const []),
      ],
    );

    expect(find.text('PULL REQUESTS'), findsNothing);
    expect(find.text('ISSUES'), findsNothing);
  });
}
