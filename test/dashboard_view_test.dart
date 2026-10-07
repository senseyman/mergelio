import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/dashboard.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/dashboard.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/workspace/dashboard_view.dart';

RepoSnapshot _snap({
  String? branch = 'main',
  String? upstream = 'origin/main',
  bool upstreamGone = false,
  int ahead = 0,
  int behind = 0,
  int changed = 0,
  int untracked = 0,
  int stashes = 0,
  RepoOp? op,
  DateTime? lastFetch,
}) => RepoSnapshot(
  summary: StatusSummary(
    branch: branch,
    detached: branch == null,
    upstream: upstream,
    upstreamGone: upstreamGone,
    ahead: ahead,
    behind: behind,
    changed: changed,
    untracked: untracked,
  ),
  stashCount: stashes,
  op: op,
  lastFetch: lastFetch,
);

/// Records what the view asks for without touching git.
class _FakeBatch extends DashboardBatchController {
  _FakeBatch(super.ref);
  final fetched = <List<String>>[];
  final pulled = <List<String>>[];
  DashboardBatch? result;
  Completer<void>? hold;

  void put(DashboardBatch? b) => state = b;

  @override
  Future<DashboardBatch?> fetchAll(
    List<String> paths, {
    required String label,
  }) async {
    fetched.add(paths);
    await hold?.future;
    state = result;
    return result;
  }

  @override
  Future<DashboardBatch?> pullAll(
    List<String> paths, {
    required String label,
  }) async {
    pulled.add(paths);
    state = result;
    return result;
  }
}

void main() {
  late WorkspaceController ws;
  late _FakeBatch batch;
  late Map<String, RepoSnapshot?> snaps;

  setUp(() {
    ws = WorkspaceController();
    snaps = {};
  });

  List<Override> overrides() => [
    workspaceProvider.overrideWith((ref) => ws),
    dashboardBatchProvider.overrideWith((ref) => batch = _FakeBatch(ref)),
    repoSnapshotProvider.overrideWith((ref, path) async {
      final s = snaps[path];
      if (s == null) throw GitException('git status failed');
      return s;
    }),
  ];

  Widget app(Widget body, {Locale? locale}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(body: body),
  );

  Widget harness() =>
      ProviderScope(overrides: overrides(), child: app(const DashboardView()));

  Future<void> pump(WidgetTester tester, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  testWidgets('shows each repository with its state', (tester) async {
    ws.openRepo('/r/api');
    ws.openRepo('/r/web');
    ws.showDashboard();
    snaps['/r/api'] = _snap(
      ahead: 1,
      behind: 3,
      changed: 2,
      untracked: 1,
      stashes: 4,
      lastFetch: DateTime.now().subtract(const Duration(hours: 2)),
    );
    snaps['/r/web'] = _snap(
      branch: 'topic',
      upstream: 'origin/topic',
      upstreamGone: true,
      op: RepoOp.rebase,
    );
    await pump(tester);

    expect(find.text('api'), findsOneWidget);
    expect(find.text('web'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('↑1 ↓3'), findsOneWidget);
    expect(find.text('2 changed'), findsOneWidget);
    expect(find.text('1 untracked'), findsOneWidget);
    expect(find.text('4 stashed'), findsOneWidget);
    expect(find.text('fetched 2h ago'), findsOneWidget);
    expect(find.text('upstream gone'), findsOneWidget);
    expect(find.text('rebasing'), findsOneWidget);
    expect(find.text('never fetched'), findsOneWidget);
    expect(find.text('clean'), findsOneWidget);
    expect(find.text('2 repositories'), findsOneWidget);
  });

  testWidgets('an unborn HEAD with no branch name reads plainly', (
    tester,
  ) async {
    ws.openRepo('/r/new');
    ws.showDashboard();
    snaps['/r/new'] = const RepoSnapshot(
      summary: StatusSummary(unborn: true),
      stashCount: 0,
    );
    await pump(tester);
    expect(find.text('no commits yet'), findsOneWidget);
    expect(find.textContaining(' · '), findsNothing);
  });

  testWidgets('says so for a repository it cannot read', (tester) async {
    ws.openRepo('/r/gone');
    ws.showDashboard();
    await pump(tester);
    expect(find.text('Could not read this repository'), findsOneWidget);
  });

  testWidgets('lists only the active group', (tester) async {
    ws.openRepo('/r/a');
    final g = ws.createGroup('Work');
    ws.setActiveGroup(g.id);
    ws.openRepo('/r/b');
    ws.showDashboard();
    snaps['/r/a'] = _snap();
    snaps['/r/b'] = _snap();
    await pump(tester);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('a'), findsNothing);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('a row click opens that repository', (tester) async {
    final a = ws.openRepo('/r/a');
    ws.openRepo('/r/b');
    ws.showDashboard();
    snaps['/r/a'] = _snap();
    snaps['/r/b'] = _snap();
    await pump(tester);
    await tester.tap(find.text('a'));
    await tester.pump();
    expect(ws.state.dashboard, isFalse);
    expect(ws.state.activeTabId, a.id);
  });

  testWidgets('fetch all and pull run over the visible repositories', (
    tester,
  ) async {
    ws.openRepo('/r/a');
    ws.openRepo('/r/b');
    ws.showDashboard();
    snaps['/r/a'] = _snap();
    snaps['/r/b'] = _snap();
    await pump(tester);
    batch.result = const DashboardBatch(DashboardBatchKind.fetch, {
      '/r/a': RowRun(RowRunState.done),
      '/r/b': RowRun(RowRunState.skipped, noRemote: true),
    });
    await tester.tap(find.text('Fetch all'));
    await tester.pumpAndSettle();
    expect(batch.fetched, [
      ['/r/a', '/r/b'],
    ]);
    expect(find.text('fetched'), findsOneWidget);
    expect(find.text('skipped: no remote'), findsOneWidget);

    batch.result = const DashboardBatch(DashboardBatchKind.pull, {
      '/r/a': RowRun(RowRunState.skipped, pullSkip: PullSkip.dirty),
      '/r/b': RowRun(RowRunState.failed, message: 'fatal: nope'),
    });
    await tester.tap(find.text('Pull fast-forwardable'));
    await tester.pumpAndSettle();
    expect(batch.pulled, [
      ['/r/a', '/r/b'],
    ]);
    expect(find.text('skipped: uncommitted changes'), findsOneWidget);
    expect(find.text('failed'), findsOneWidget);
    expect(find.text('fatal: nope'), findsOneWidget);
  });

  for (final (locale, text) in [
    (const Locale('en'), 'An operation is already running'),
    (const Locale('uk'), 'Операція вже виконується'),
  ]) {
    testWidgets('a refused batch says so in ${locale.languageCode}', (
      tester,
    ) async {
      ws.openRepo('/r/a');
      ws.showDashboard();
      snaps['/r/a'] = _snap();
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: app(const DashboardView(), locale: locale),
        ),
      );
      await tester.pumpAndSettle();
      // The controller refuses (another batch or a lane got there first).
      batch.result = null;
      await tester.tap(find.byType(OutlinedButton).first);
      await tester.pump();
      final toasts = container.read(toastProvider);
      expect(toasts.single.title, text);
      expect(toasts.single.kind, ToastKind.warning);
      await tester.pump(const Duration(seconds: 7));
    });
  }

  testWidgets('buttons are disabled while a batch or a lane is busy', (
    tester,
  ) async {
    ws.openRepo('/r/a');
    ws.showDashboard();
    snaps['/r/a'] = _snap();
    await pump(tester);
    batch.put(
      const DashboardBatch(DashboardBatchKind.fetch, {
        '/r/a': RowRun(RowRunState.running),
      }),
    );
    await tester.pump();
    await tester.tap(find.text('Fetch all'));
    await tester.tap(find.text('Pull fast-forwardable'));
    await tester.pump();
    expect(batch.fetched, isEmpty);
    expect(batch.pulled, isEmpty);

    batch.put(null);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardView)),
    );
    container.read(busyProvider.notifier).state = const BusyState('Commit');
    await tester.pump();
    await tester.tap(find.text('Pull fast-forwardable'));
    await tester.pump();
    expect(batch.pulled, isEmpty);
  });

  testWidgets('leaving the dashboard mid-batch is safe', (tester) async {
    final a = ws.openRepo('/r/a');
    ws.showDashboard();
    snaps['/r/a'] = _snap();
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: app(const DashboardView()),
      ),
    );
    await tester.pumpAndSettle();
    batch.hold = Completer<void>();
    batch.result = const DashboardBatch(DashboardBatchKind.fetch, {
      '/r/a': RowRun(RowRunState.done),
    });
    await tester.tap(find.text('Fetch all'));
    await tester.pump();
    // The user opens a repository while the batch is still running.
    ws.setActive(a.id);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: app(const SizedBox()),
      ),
    );
    expect(find.byType(DashboardView), findsNothing);
    batch.hold!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The summary still reaches the user.
    expect(container.read(toastProvider), hasLength(1));
    // Let the toast's dismiss timer run out.
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('fits every width down to the narrowest column', (tester) async {
    final g = ws.createGroup('A group with a rather long name indeed');
    ws.setActiveGroup(g.id);
    ws.openRepo('/r/a-repository-with-a-long-name');
    ws.showDashboard();
    snaps['/r/a-repository-with-a-long-name'] = _snap(
      branch: 'feature/a-rather-long-branch-name',
      ahead: 12,
      behind: 340,
      changed: 120,
      untracked: 33,
      stashes: 9,
      op: RepoOp.cherryPick,
      lastFetch: DateTime.now(),
    );
    for (final w in [336.0, 480.0, 800.0, 1400.0]) {
      await pump(tester, width: w);
      expect(tester.takeException(), isNull, reason: 'width $w');
    }
  });
}
