import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/forge_refresh.dart';
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

    // SidebarSection renders its label upper-cased, so this is the string a
    // rendered header would actually produce. Asserting the mixed-case form
    // would pass no matter what the widget did.
    expect(find.text('PULL REQUESTS'), findsNothing);
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
        // Connected, so the row list is genuinely empty rather than holding
        // the connect hint — this is [SidebarSection]'s own empty-state
        // text firing, not a second copy of the message rendered here.
        forgeTokenProvider.overrideWith(
          (ref, path) async => const ForgeToken('ghp_x'),
        ),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => const ForgePanel(),
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(find.text('No open pull requests'), findsOneWidget);
  });

  testWidgets(
    'renders the empty-state text exactly once, not once from the section '
    'and once from SidebarSection',
    (t) async {
      await _pump(
        t,
        overrides: [
          forgeHostProvider.overrideWith((ref, path) async => _host),
          forgeTokenProvider.overrideWith(
            (ref, path) async => const ForgeToken('ghp_x'),
          ),
          pullRequestPanelProvider.overrideWith(
            (ref, path) async => const ForgePanel(),
          ),
        ],
      );
      await t.pumpAndSettle();

      // A regression guard for a duplicate rendering of the same string:
      // the row list itself must come back empty so SidebarSection is the
      // only thing that ever draws this text.
      expect(find.text('No open pull requests'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SidebarSection),
          matching: find.text('No open pull requests'),
        ),
        findsOneWidget,
      );
    },
  );

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

    // Pinned to the exact localized hint, not a loose substring: any text
    // containing "Preferences" would satisfy the old assertion even if the
    // hint's own wording changed or dropped out of the tree entirely.
    final l = AppLocalizations.of(
      t.element(find.byType(ForgePullRequestSection)),
    );
    expect(
      find.text(l.forgeConnectHint),
      findsOneWidget,
      reason: 'an unauthenticated session must be told why it is limited',
    );
  });

  testWidgets('hides the connect hint once a token is present', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith(
          (ref, path) async => const ForgeToken('ghp_x'),
        ),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => ForgePanel(pullRequests: [_pr(1)]),
        ),
      ],
    );
    await t.pumpAndSettle();

    final l = AppLocalizations.of(
      t.element(find.byType(ForgePullRequestSection)),
    );
    expect(
      find.text(l.forgeConnectHint),
      findsNothing,
      reason: 'a connected session has no reason to be told to connect',
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

    // The spinner renders while the fetch is in flight, not the
    // empty-state message that would falsely claim there is nothing open.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No open pull requests'), findsNothing);

    completer.complete(const ForgePanel());
    await t.pumpAndSettle();
  });

  testWidgets('a refresh control re-fetches the panel', (t) async {
    var calls = 0;
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        // A token on file, not null: refreshNow (which the button goes
        // through) declines to spend a fetch on an anonymous session, so an
        // unauthenticated repeat of this test would see the tap do nothing.
        forgeTokenProvider.overrideWith(
          (ref, path) async => const ForgeToken('ghp_x'),
        ),
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

  testWidgets(
    'a press while a refresh is already in flight is absorbed by it',
    (t) async {
      // Each refresh here is a completer the test controls, so one can be
      // left running while a second press lands on top of it.
      final completers = <Completer<ForgePanel>>[];
      await _pump(
        t,
        overrides: [
          forgeHostProvider.overrideWith((ref, path) async => _host),
          forgeTokenProvider.overrideWith(
            (ref, path) async => const ForgeToken('ghp_x'),
          ),
          pullRequestPanelProvider.overrideWith((ref, path) {
            final c = Completer<ForgePanel>();
            completers.add(c);
            return c.future;
          }),
        ],
      );
      await t.pump();
      expect(completers, hasLength(1));
      completers.single.complete(const ForgePanel());
      await t.pumpAndSettle();

      // This press starts a refresh that is left running.
      await t.tap(find.byTooltip('Refresh'));
      await t.pump();
      expect(completers, hasLength(2));

      // The control must show that a refresh is already under way, not sit
      // there looking identical to the idle state.
      final button = t.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(
        button.onPressed,
        isNull,
        reason:
            'a refresh already in flight must be visible on the control, '
            'not just silently absorbed',
      );

      // A second press while that refresh is still running must not spend
      // another one — the panel provider would otherwise be re-invalidated
      // mid-flight and burn a second ~21-request budget for nothing.
      await t.tap(find.byTooltip('Refresh'));
      await t.pump();
      expect(
        completers,
        hasLength(2),
        reason:
            'a press while a refresh is already running must be absorbed '
            'by it, not spend a second one',
      );

      completers.last.complete(const ForgePanel());
      await t.pumpAndSettle();
    },
  );

  testWidgets('the refresh control works without a token, because a press '
      'is the request', (t) async {
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

    expect(
      calls,
      2,
      reason:
          'pressing refresh IS the request for these rows; refusing it for '
          'want of a token would leave a control that silently does nothing',
    );
  });

  testWidgets('does not fetch the panel while the section is collapsed', (
    t,
  ) async {
    var calls = 0;
    late SettingsController ctl;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (_) => ctl = SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(collapsedSections: {'pull-requests': true}),
            ),
          ),
          forgeHostProvider.overrideWith((ref, path) async => _host),
          forgeTokenProvider.overrideWith((ref, path) async => null),
          pullRequestPanelProvider.overrideWith((ref, path) async {
            calls++;
            return const ForgePanel();
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: ForgePullRequestSection(repoPath: '/repo'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(
      calls,
      0,
      reason:
          'a collapsed section is not visible, so it must not spend a '
          'forge request fetching rows nobody can see',
    );

    ctl.toggleSection('pull-requests');
    await t.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('a refresh goes through the scheduler, not a bare invalidate', (
    t,
  ) async {
    // A bare `ref.invalidate(pullRequestPanelProvider(...))` would also
    // refetch the panel, so that alone cannot tell the two apart (see the
    // test above). Routing through the scheduler matters because refreshNow
    // also resets its backoff and re-arms its timer — this spy stands in for
    // the real controller and records only that the button reached it, with
    // the repository path the button owns.
    _SpyForgeRefreshController? spy;
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => const ForgePanel(),
        ),
        forgeRefreshProvider.overrideWith((ref) {
          final c = _SpyForgeRefreshController(ref);
          spy = c;
          return c;
        }),
      ],
    );
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Refresh'));
    await t.pumpAndSettle();

    expect(
      spy?.refreshNowCalls,
      ['/repo'],
      reason:
          'the refresh button must call refreshNow on the scheduler for '
          "the section's own repository path, not invalidate the panel "
          'directly',
    );
  });

  testWidgets('opening a pull request goes through the launch seam', (t) async {
    final opened = <Uri>[];
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => ForgePanel(pullRequests: [_pr(7)]),
        ),
        forgeLaunchUrlProvider.overrideWithValue((url) async {
          opened.add(url);
          return true;
        }),
      ],
    );
    await t.pumpAndSettle();

    await t.tap(find.text('request 7'));
    await t.pump();

    expect(opened, hasLength(1));
    expect(opened.single.toString(), contains('/pull/7'));
  });

  testWidgets('a launch that could not be handled is reported, not silent', (
    t,
  ) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => ForgePanel(pullRequests: [_pr(7)]),
        ),
        // Exactly what happens on a machine with no browser handler
        // registered: nothing throws, the future just resolves false.
        forgeLaunchUrlProvider.overrideWithValue((url) async => false),
      ],
    );
    await t.pumpAndSettle();

    final container = ProviderScope.containerOf(
      t.element(find.byType(ForgePullRequestSection)),
    );

    await t.tap(find.text('request 7'));
    await t.pump();

    expect(container.read(toastProvider), hasLength(1));
    expect(container.read(toastProvider).single.kind, ToastKind.error);
  });
}

/// Records calls instead of performing them, so a test can tell the refresh
/// button actually reached the scheduler rather than something that merely
/// has the same visible effect (refetching the panel).
class _SpyForgeRefreshController extends ForgeRefreshController {
  final refreshNowCalls = <String>[];

  _SpyForgeRefreshController(super.ref);

  @override
  void refreshNow(String path) => refreshNowCalls.add(path);
}
