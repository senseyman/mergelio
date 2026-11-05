import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/review.dart';
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

const _request = PullRequest(
  number: 7,
  title: 'request 7',
  state: PullRequestState.open,
  author: ForgeUser(login: 'me'),
  sourceBranch: 'feature/7',
  targetBranch: 'release/1.x',
  headSha: 'sha7',
);

typedef _Fetch = (String, ForgeKind, int, String);

/// The section with one request row. Fetching and the browser are behind
/// seams, so nothing here runs git or launches anything.
Future<(ProviderContainer, List<_Fetch>, List<Uri>)> _pump(
  WidgetTester tester,
  ForgeHost host, {
  ({String base, String head})? result = (base: 'B', head: 'H'),
}) async {
  final fetches = <_Fetch>[];
  final opened = <Uri>[];
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        (_) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
      repoDataProvider('/repo').overrideWith(
        (ref) async =>
            const RepoData(branches: [Branch(name: 'main', current: true)]),
      ),
      forgeHostProvider.overrideWith((ref, path) async => host),
      forgeTokenProvider.overrideWith((ref, path) async => null),
      pullRequestPanelProvider.overrideWith(
        (ref, path) async => const ForgePanel(pullRequests: [_request]),
      ),
      forgeLaunchUrlProvider.overrideWithValue((url) async {
        opened.add(url);
        return true;
      }),
      forgeFetchPullRequestForReviewProvider.overrideWithValue((
        repoPath,
        kind,
        number,
        targetBranch,
      ) async {
        fetches.add((repoPath, kind, number, targetBranch));
        return result;
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(body: ForgePullRequestSection(repoPath: '/repo')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, fetches, opened);
}

Future<void> _menu(WidgetTester tester) async {
  await tester.tap(find.text('request 7'), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reviewing a request opens it in the review view', (
    tester,
  ) async {
    final (c, fetches, opened) = await _pump(tester, _github);

    await _menu(tester);
    await tester.tap(find.text('Review in Mergelio'));
    await tester.pumpAndSettle();

    expect(fetches, [('/repo', ForgeKind.github, 7, 'release/1.x')]);
    expect(
      c.read(reviewTargetProvider),
      const ReviewTarget(
        repoPath: '/repo',
        base: 'B',
        head: 'H',
        pullRequest: ReviewPullRequest(
          kind: ForgeKind.github,
          number: 7,
          targetBranch: 'release/1.x',
        ),
      ),
    );
    expect(opened, isEmpty);
  });

  testWidgets('a merge request is reviewed the same way', (tester) async {
    final (c, fetches, _) = await _pump(tester, _gitlab);

    await _menu(tester);
    await tester.tap(find.text('Review in Mergelio'));
    await tester.pumpAndSettle();

    expect(fetches.single.$2, ForgeKind.gitlab);
    expect(c.read(reviewTargetProvider)?.headLabel, '!7');
  });

  testWidgets('a failed fetch leaves the centre column alone', (tester) async {
    final (c, fetches, _) = await _pump(tester, _github, result: null);

    await _menu(tester);
    await tester.tap(find.text('Review in Mergelio'));
    await tester.pumpAndSettle();

    expect(fetches, hasLength(1));
    expect(c.read(reviewTargetProvider), isNull);
  });

  testWidgets('a plain click still opens the browser', (tester) async {
    final (c, fetches, opened) = await _pump(tester, _github);

    await tester.tap(find.text('request 7'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(fetches, isEmpty);
    expect(c.read(reviewTargetProvider), isNull);
  });
}
