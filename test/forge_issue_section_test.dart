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
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/forge_refresh.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/forge_issue_section.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';
import 'package:mergelio/ui/workspace/sidebar_section.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

Issue _issue(int n, {List<String> labels = const []}) => Issue(
  number: n,
  title: 'issue $n',
  state: IssueState.open,
  author: const ForgeUser(login: 'me'),
  labels: labels,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        home: const Scaffold(body: ForgeIssueSection(repoPath: '/repo')),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('tapping a row opens that issue on the web', (t) async {
    final opened = <Uri>[];
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        issuePanelProvider.overrideWith((ref, path) async => [_issue(12)]),
        forgeLaunchUrlProvider.overrideWithValue((url) async {
          opened.add(url);
          return true;
        }),
      ],
    );
    await t.pumpAndSettle();

    await t.tap(find.text('issue 12'));
    await t.pumpAndSettle();

    expect(
      opened.single.toString(),
      'https://github.com/o/r/issues/12',
      reason:
          'the row must reach the issue page, not the pull request page a '
          'forge serves at the same number',
    );
  });

  testWidgets('a tap nothing can handle says so', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        issuePanelProvider.overrideWith((ref, path) async => [_issue(12)]),
        forgeLaunchUrlProvider.overrideWithValue((url) async => false),
      ],
    );
    await t.pumpAndSettle();

    final container = ProviderScope.containerOf(
      t.element(find.byType(ForgeIssueSection)),
    );

    await t.tap(find.text('issue 12'));
    await t.pump();

    // Without this the tap looks like it simply did nothing.
    expect(container.read(toastProvider), hasLength(1));
    expect(container.read(toastProvider).single.kind, ToastKind.error);
    // Naming issues, not pull requests: this section began as a copy of
    // that one, and the borrowed string would still read plausibly here.
    expect(container.read(toastProvider).single.title, contains('issue'));
  });

  testWidgets('renders nothing for a repository not on a forge', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => null),
        issuePanelProvider.overrideWith((ref, path) async => const []),
      ],
    );
    await t.pumpAndSettle();

    expect(find.text('ISSUES'), findsNothing);
    expect(find.byType(SidebarSection), findsNothing);
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
              const AppSettings(collapsedSections: {'issues': true}),
            ),
          ),
          forgeHostProvider.overrideWith((ref, path) async => _host),
          issuePanelProvider.overrideWith((ref, path) async {
            calls++;
            return const [];
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: ForgeIssueSection(repoPath: '/repo')),
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

    ctl.toggleSection('issues');
    await t.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('lists each open issue with its number, title and labels', (
    t,
  ) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        issuePanelProvider.overrideWith(
          (ref, path) async => [
            _issue(12, labels: const ['bug', 'p1']),
            _issue(3),
          ],
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(find.text('#12'), findsOneWidget);
    expect(find.text('issue 12'), findsOneWidget);
    expect(find.text('issue 3'), findsOneWidget);
    expect(find.textContaining('bug'), findsOneWidget);
    expect(find.textContaining('p1'), findsOneWidget);
  });

  testWidgets('says so when there is nothing open', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        issuePanelProvider.overrideWith((ref, path) async => const []),
      ],
    );
    await t.pumpAndSettle();

    expect(find.text('No open issues'), findsOneWidget);
  });

  testWidgets('shows a failure in the words the panel owns, not its detail', (
    t,
  ) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        issuePanelProvider.overrideWith(
          (ref, path) async => throw const ForgeOffline('token=abc123'),
        ),
      ],
    );
    await t.pumpAndSettle();

    expect(find.textContaining('Could not reach GitHub'), findsOneWidget);
    expect(find.textContaining('abc123'), findsNothing);
  });

  testWidgets('the count hides while the panel is still loading', (t) async {
    final completer = Completer<List<Issue>>();
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        issuePanelProvider.overrideWith((ref, path) => completer.future),
      ],
    );
    await t.pump();

    expect(find.text('0'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await t.pumpAndSettle();
  });

  testWidgets('shows no connect-token hint of its own', (t) async {
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        issuePanelProvider.overrideWith((ref, path) async => [_issue(1)]),
      ],
    );
    await t.pumpAndSettle();

    final l = AppLocalizations.of(t.element(find.byType(ForgeIssueSection)));
    expect(find.text(l.forgeConnectHint), findsNothing);
  });

  testWidgets('a refresh control goes through the scheduler', (t) async {
    _SpyForgeRefreshController? spy;
    await _pump(
      t,
      overrides: [
        forgeHostProvider.overrideWith((ref, path) async => _host),
        issuePanelProvider.overrideWith((ref, path) async => const []),
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

    expect(spy?.refreshNowCalls, ['/repo']);
  });

  testWidgets(
    'a press while a refresh is already in flight is absorbed by it',
    (t) async {
      final completers = <Completer<List<Issue>>>[];
      await _pump(
        t,
        overrides: [
          forgeHostProvider.overrideWith((ref, path) async => _host),
          issuePanelProvider.overrideWith((ref, path) {
            final c = Completer<List<Issue>>();
            completers.add(c);
            return c.future;
          }),
        ],
      );
      await t.pump();
      expect(completers, hasLength(1));
      completers.single.complete(const []);
      await t.pumpAndSettle();

      await t.tap(find.byTooltip('Refresh'));
      await t.pump();
      expect(completers, hasLength(2));

      final button = t.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(button.onPressed, isNull);

      completers.last.complete(const []);
      await t.pumpAndSettle();
    },
  );
}

class _SpyForgeRefreshController extends ForgeRefreshController {
  final refreshNowCalls = <String>[];

  _SpyForgeRefreshController(super.ref);

  @override
  void refreshNow(String path) => refreshNowCalls.add(path);
}
