import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/recents.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/app_tab_bar.dart';

import 'support/memory_recents.dart';

/// Every folder is a repository except one whose path says it is gone.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => !path.contains('gone');
}

const _alpha = RecentRepo(name: 'alpha', path: '/r/alpha');
const _beta = RecentRepo(name: 'beta', path: '/r/beta');

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<RecentRepo> recents = const [_alpha, _beta],
  List<String> open = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [
      gitServiceProvider.overrideWithValue(_FakeGit()),
      recentsProvider.overrideWith(
        (ref) => RecentsController(MemoryRecents(), recents),
      ),
    ],
  );
  addTearDown(c.dispose);
  for (final path in open) {
    c.read(workspaceProvider.notifier).openRepo(path);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(
          body: Align(alignment: Alignment.topLeft, child: AddRepositoryMenu()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> _openRecent(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add repository'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open recent'));
  await tester.pumpAndSettle();
}

List<String> _tabPaths(ProviderContainer c) => [
  for (final t in c.read(workspaceProvider).tabs) t.path,
];

void main() {
  testWidgets('the + menu offers open, clone, create and open recent', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Add repository'));
    await tester.pumpAndSettle();

    expect(find.text('Open…'), findsOneWidget);
    expect(find.text('Clone…'), findsOneWidget);
    expect(find.text('Create…'), findsOneWidget);
    expect(find.text('Open recent'), findsOneWidget);
  });

  testWidgets('open recent lists recents by name, with their path', (
    tester,
  ) async {
    await _pump(tester);

    await _openRecent(tester);

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('/r/alpha'), findsOneWidget);
  });

  testWidgets('a repository already open is not listed', (tester) async {
    await _pump(tester, open: ['/r/alpha']);

    await _openRecent(tester);

    expect(find.text('beta'), findsOneWidget);
    expect(find.text('alpha'), findsNothing);
  });

  testWidgets('choosing a recent opens it in a tab', (tester) async {
    final c = await _pump(tester);

    await _openRecent(tester);
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();

    expect(_tabPaths(c), ['/r/beta']);
    expect(c.read(recentsProvider).first.path, '/r/beta');
    expect(find.text('alpha'), findsNothing, reason: 'the menu closes');
  });

  testWidgets('a recent that is no longer a repository says so', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      recents: const [RecentRepo(name: 'gone', path: '/r/gone')],
    );

    await _openRecent(tester);
    await tester.tap(find.text('gone'));
    await tester.pumpAndSettle();

    expect(c.read(toastProvider).single.kind, ToastKind.error);
    expect(_tabPaths(c), isEmpty);
    // Let the toast time out so no timer outlives the test.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('with nothing to reopen, open recent is shown but disabled', (
    tester,
  ) async {
    await _pump(tester, recents: const [_alpha], open: ['/r/alpha']);

    await tester.tap(find.byTooltip('Add repository'));
    await tester.pumpAndSettle();
    final submenu = tester.widget<SubmenuButton>(
      find.ancestor(
        of: find.text('Open recent'),
        matching: find.byType(SubmenuButton),
      ),
    );

    expect(submenu.menuChildren, isEmpty);
    await tester.tap(find.text('Open recent'));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsNothing);
  });

  testWidgets('long names and paths do not overflow', (tester) async {
    final long = 'x' * 120;
    await _pump(
      tester,
      recents: [RecentRepo(name: long, path: '/r/$long')],
    );

    await _openRecent(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(long), findsOneWidget);
  });

  testWidgets('the menu opens below the + rather than over it', (tester) async {
    await _pump(tester);
    final button = tester.getRect(find.byTooltip('Add repository'));

    await tester.tap(find.byTooltip('Add repository'));
    await tester.pumpAndSettle();

    final first = tester.getRect(find.text('Open…'));
    expect(first.top, greaterThanOrEqualTo(button.bottom));
  });

  testWidgets('the + reads as a button to assistive tech', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(
      tester.getSemantics(find.byTooltip('Add repository')),
      isSemantics(isButton: true, tooltip: 'Add repository'),
    );
    semantics.dispose();
  });
}
