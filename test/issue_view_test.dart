import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/issue_view.dart';
import 'package:mergelio/ui/issue/issue_view.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';

import 'support/fake_forge.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

IssueDetail _detail({
  IssueState state = IssueState.open,
  String body = 'Steps to reproduce',
}) => IssueDetail(
  issue: Issue(
    number: 3,
    title: 'Crash on open',
    state: state,
    author: const ForgeUser(login: 'ann'),
    labels: const ['bug'],
  ),
  body: body,
);

typedef _Harness = ({ProviderContainer c, FakeForge? forge, List<Uri> opened});

Future<_Harness> _pump(
  WidgetTester tester, {
  IssueDetail? detail,
  ForgeError? error,
  bool offForge = false,
  bool launchSucceeds = true,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final forge = offForge
      ? null
      : FakeForge(
          host: _host,
          issueDetails: {3: detail ?? _detail()},
          issueError: error,
        );
  final opened = <Uri>[];
  final c = ProviderContainer(
    overrides: [
      forgeProvider.overrideWith((ref, path) async => forge),
      forgeHostProvider.overrideWith(
        (ref, path) async => offForge ? null : _host,
      ),
      forgeLaunchUrlProvider.overrideWithValue((url) async {
        opened.add(url);
        return launchSucceeds;
      }),
      issueTargetProvider.overrideWith((ref) => (repoPath: '/repo', number: 3)),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(body: IssueView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (c: c, forge: forge, opened: opened);
}

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(IssueView)));

void main() {
  testWidgets('shows number, title, state, author and labels', (tester) async {
    await _pump(tester);

    expect(find.text('#3'), findsOneWidget);
    expect(find.text('Crash on open'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.textContaining('ann'), findsOneWidget);
    expect(find.textContaining('bug'), findsOneWidget);
  });

  testWidgets('a closed issue says Closed', (tester) async {
    await _pump(tester, detail: _detail(state: IssueState.closed));

    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('renders the description as Markdown', (tester) async {
    await _pump(tester, detail: _detail(body: '# Heading'));

    expect(find.text('Heading'), findsOneWidget);
    expect(find.text('# Heading'), findsNothing);
  });

  testWidgets('an empty description says so', (tester) async {
    await _pump(tester, detail: _detail(body: '  '));

    expect(find.text(_l(tester).rvPrNoDescription), findsOneWidget);
  });

  testWidgets('a forge failure is worded like the sidebar', (tester) async {
    await _pump(tester, error: const ForgeNotVisible());

    expect(
      find.text(
        forgePanelMessage(const ForgeNotVisible(), _l(tester), _host.server),
      ),
      findsOneWidget,
    );
    expect(find.text('Crash on open'), findsNothing);
  });

  testWidgets('off any forge, says it could not be read', (tester) async {
    await _pump(tester, offForge: true);

    expect(find.text(_l(tester).issueViewNoForge), findsOneWidget);
    expect(find.text(_l(tester).rvPrNoDescription), findsNothing);
  });

  testWidgets('close puts the issue away', (tester) async {
    final h = await _pump(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(h.c.read(issueTargetProvider), isNull);
  });

  testWidgets('the browser control opens the issue page', (tester) async {
    final h = await _pump(tester);

    await tester.tap(find.byTooltip('Open in browser'));
    await tester.pumpAndSettle();

    expect(h.opened.single.path, '/o/r/issues/3');
  });

  testWidgets('a launch nothing handled is reported', (tester) async {
    final h = await _pump(tester, launchSucceeds: false);

    await tester.tap(find.byTooltip('Open in browser'));
    await tester.pumpAndSettle();

    expect(h.c.read(toastProvider).single.kind, ToastKind.error);
    // Let the toast time out so no timer outlives the test.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('refresh reads the issue again', (tester) async {
    final h = await _pump(tester);

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(h.forge!.issueCalls, 2);
  });

  testWidgets('fits narrow centre columns', (tester) async {
    await _pump(tester);
    for (final width in [336.0, 800.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at $width');
    }
  });
}
