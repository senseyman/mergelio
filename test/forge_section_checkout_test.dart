import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/forge/pull_request_ref.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';
import 'package:mergelio/ui/workspace/forge_section.dart';

const _github = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

const _gitlab = ForgeHost(
  kind: ForgeKind.gitlab,
  host: 'gitlab.com',
  owner: 'g',
  repo: 'r',
);

PullRequest _pr(int n) => PullRequest(
  number: n,
  title: 'request $n',
  state: PullRequestState.open,
  author: const ForgeUser(login: 'me'),
  sourceBranch: 'feature/$n',
  targetBranch: 'main',
  headSha: 'sha$n',
);

class _Calls {
  final checkouts = <(String, ForgeKind, int, bool)>[];
  final opened = <Uri>[];
}

/// The section with a forge row for request 7. Checkout and the browser are
/// both behind seams, so nothing here runs git or launches anything.
Future<_Calls> _pump(
  WidgetTester tester,
  ForgeHost host, {
  PullRequestCheckout firstResult = const PullRequestCheckout(
    PullRequestCheckoutOutcome.done,
  ),
  String currentBranch = 'main',
  bool confirmDestructive = true,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (_) => SettingsController(
            InMemorySettingsRepository(),
            AppSettings(confirmDestructive: confirmDestructive),
          ),
        ),
        repoDataProvider('/repo').overrideWith(
          (ref) async =>
              RepoData(branches: [Branch(name: currentBranch, current: true)]),
        ),
        forgeHostProvider.overrideWith((ref, path) async => host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => ForgePanel(pullRequests: [_pr(7)]),
        ),
        forgeLaunchUrlProvider.overrideWithValue((url) async {
          calls.opened.add(url);
          return true;
        }),
        forgeCheckoutPullRequestProvider.overrideWithValue((
          repoPath,
          kind,
          number, {
          bool replace = false,
        }) async {
          calls.checkouts.add((repoPath, kind, number, replace));
          return calls.checkouts.length == 1
              ? firstResult
              : const PullRequestCheckout(PullRequestCheckoutOutcome.done);
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(body: ForgePullRequestSection(repoPath: '/repo')),
      ),
    ),
  );
  // The sidebar keeps the repository loaded in the app; stand in for it so
  // the menu sees which branch is checked out.
  ProviderScope.containerOf(
    tester.element(find.byType(ForgePullRequestSection)),
  ).listen(repoDataProvider('/repo'), (_, _) {});
  await tester.pumpAndSettle();
  return calls;
}

Future<void> _menu(WidgetTester tester) async {
  await tester.tap(find.text('request 7'), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a pull request row checks the request out as pr/<n>', (
    tester,
  ) async {
    final calls = await _pump(tester, _github);

    await _menu(tester);
    await tester.tap(find.text('Check out locally as pr/7'));
    await tester.pumpAndSettle();

    expect(calls.checkouts, [('/repo', ForgeKind.github, 7, false)]);
    expect(calls.opened, isEmpty);
  });

  testWidgets('a merge request row checks the request out as mr/<n>', (
    tester,
  ) async {
    final calls = await _pump(tester, _gitlab);

    await _menu(tester);
    await tester.tap(find.text('Check out locally as mr/7'));
    await tester.pumpAndSettle();

    expect(calls.checkouts, [('/repo', ForgeKind.gitlab, 7, false)]);
  });

  testWidgets('the menu still opens the request in the browser', (
    tester,
  ) async {
    final calls = await _pump(tester, _github);

    await _menu(tester);
    await tester.tap(find.text('Open in browser'));
    await tester.pumpAndSettle();

    expect(calls.opened.single.path, '/o/r/pull/7');
    expect(calls.checkouts, isEmpty);
  });

  testWidgets('a right-click alone neither checks out nor opens', (
    tester,
  ) async {
    final calls = await _pump(tester, _github);

    await _menu(tester);

    expect(calls.checkouts, isEmpty);
    expect(calls.opened, isEmpty);
  });

  testWidgets('a plain click still opens the browser', (tester) async {
    final calls = await _pump(tester, _github);

    await tester.tap(find.text('request 7'));
    await tester.pumpAndSettle();

    expect(calls.opened, hasLength(1));
    expect(calls.checkouts, isEmpty);
  });

  testWidgets('on its own branch already, the entry offers an update', (
    tester,
  ) async {
    final calls = await _pump(tester, _github, currentBranch: 'pr/7');

    await _menu(tester);
    expect(find.text('Check out locally as pr/7'), findsNothing);
    await tester.tap(find.text('Update pr/7'));
    await tester.pumpAndSettle();

    expect(calls.checkouts, [('/repo', ForgeKind.github, 7, false)]);
  });

  group('a force-pushed request', () {
    const diverged = PullRequestCheckout(
      PullRequestCheckoutOutcome.diverged,
      localOnly: 2,
    );

    testWidgets('asks before replacing, and replaces on yes', (tester) async {
      final calls = await _pump(tester, _github, firstResult: diverged);

      await _menu(tester);
      await tester.tap(find.text('Check out locally as pr/7'));
      await tester.pumpAndSettle();

      expect(find.text('Replace pr/7?'), findsOneWidget);
      expect(find.textContaining('2 commits'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(calls.checkouts, [
        ('/repo', ForgeKind.github, 7, false),
        ('/repo', ForgeKind.github, 7, true),
      ]);
    });

    testWidgets('a no leaves the local branch alone', (tester) async {
      final calls = await _pump(tester, _github, firstResult: diverged);

      await _menu(tester);
      await tester.tap(find.text('Check out locally as pr/7'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(calls.checkouts, [('/repo', ForgeKind.github, 7, false)]);
    });

    testWidgets('a clean checkout never asks', (tester) async {
      final calls = await _pump(tester, _github);

      await _menu(tester);
      await tester.tap(find.text('Check out locally as pr/7'));
      await tester.pumpAndSettle();

      expect(find.text('Replace pr/7?'), findsNothing);
      expect(calls.checkouts, hasLength(1));
    });
  });
}
