import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge.dart';
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
  final checkouts = <(String, ForgeKind, int)>[];
  final opened = <Uri>[];
}

/// The section with a forge row for request 7. Checkout and the browser are
/// both behind seams, so nothing here runs git or launches anything.
Future<_Calls> _pump(WidgetTester tester, ForgeHost host) async {
  final calls = _Calls();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (_) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
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
          number,
        ) async {
          calls.checkouts.add((repoPath, kind, number));
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

    expect(calls.checkouts, [('/repo', ForgeKind.github, 7)]);
    expect(calls.opened, isEmpty);
  });

  testWidgets('a merge request row checks the request out as mr/<n>', (
    tester,
  ) async {
    final calls = await _pump(tester, _gitlab);

    await _menu(tester);
    await tester.tap(find.text('Check out locally as mr/7'));
    await tester.pumpAndSettle();

    expect(calls.checkouts, [('/repo', ForgeKind.gitlab, 7)]);
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
}
