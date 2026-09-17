import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/forge_section.dart';
import 'package:mergelio/ui/workspace/sidebar_section.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

PullRequest _pr(int n, {PullRequestState state = PullRequestState.open}) =>
    PullRequest(
      number: n,
      title: 'request $n',
      state: state,
      author: const ForgeUser(login: 'me'),
      sourceBranch: 'feature/$n',
      targetBranch: 'main',
      headSha: 'sha$n',
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The section reads collapse state and a toggle notifier off the
        // real controller; the default provider throws until something
        // supplies one.
        settingsProvider.overrideWith(
          (_) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(body: ForgePullRequestSection(repoPath: '/repo')),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders nothing for a repository not on a forge', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => null),
        // Covers the guard actually taking the null-host branch: without
        // this override, a guard that failed to short-circuit would watch
        // the real provider, throw under testWidgets, and leave the header
        // absent for the wrong reason — the assertions below could not
        // tell the two apart.
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => const ForgePanel(),
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(find.text('Pull requests'), findsNothing);
    expect(find.byType(SidebarSection), findsNothing);
  });

  testWidgets('lists each open request', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => ForgePanel(
            pullRequests: [_pr(7), _pr(8)],
            checksBySha: const {
              'sha7': ChecksSummary(overall: ChecksOverall.failure),
            },
          ),
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(find.text('request 7'), findsOneWidget);
    expect(find.text('request 8'), findsOneWidget);
    expect(find.text('#7'), findsOneWidget);

    // request 7 failed CI and must show a failure badge, never a success
    // one; request 8 has no checks at all and shows neither.
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('says so when there is nothing open', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => const ForgePanel(),
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(find.text('No open pull requests'), findsOneWidget);
  });

  testWidgets('offers a hint when no token is connected', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => ForgePanel(pullRequests: [_pr(1)]),
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(
      find.textContaining('Preferences'),
      findsOneWidget,
      reason: 'an unauthenticated session must be told why it is limited',
    );
  });

  testWidgets('shows a failure in the words the panel owns', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => throw const ForgeUnauthenticated(),
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(find.textContaining('rejected the saved token'), findsOneWidget);
  });

  testWidgets('does not echo an error detail that could carry a secret', (
    t,
  ) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => throw const ForgeOffline('token=abc123'),
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(find.textContaining('abc123'), findsNothing);
  });

  testWidgets('the count hides while the panel is still loading', (t) async {
    final completer = Completer<ForgePanel>();
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith((ref, path) => completer.future),
      ],
    );
    await t.pump();

    // Nothing has resolved yet: no digit anywhere claims a count, in
    // particular not a false "0" while the fetch is still in flight.
    expect(find.text('0'), findsNothing);

    completer.complete(const ForgePanel());
    await t.pumpAndSettle();
  });

  testWidgets('a refresh control re-fetches the panel', (t) async {
    var calls = 0;
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith((ref, path) async {
          calls++;
          return const ForgePanel();
        }),
      ],
    );
    await t.pumpAndSettle();
    expect(calls, 1);

    await t.tap(find.byTooltip('Refresh'));
    await t.pumpAndSettle();

    expect(calls, 2);
  });
}
