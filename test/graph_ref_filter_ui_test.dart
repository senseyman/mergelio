import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/graph_ref_filter.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/graph_ref_filter.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/graph/graph_ref_filter_bar.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _data = RepoData(
  branches: [
    Branch(name: 'main', current: true),
    Branch(name: 'feat'),
  ],
  remotes: ['origin'],
  remoteBranches: [RemoteBranch(remote: 'origin', branch: 'feat')],
);

Widget _app(Widget home) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
    worktreeByBranchProvider('/r')
        .overrideWithValue(const <String, Worktree>{}),
    repoDataProvider('/r').overrideWith((ref) async => _data),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(body: home),
  ),
);

Future<ProviderContainer> _pumpSidebar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(RepoSidebar(onCollapse: () {})));
  final c = ProviderScope.containerOf(tester.element(find.byType(RepoSidebar)));
  c.read(workspaceProvider.notifier).openRepo('/r');
  await tester.pumpAndSettle();
  return c;
}

Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final g = await tester.startGesture(
    tester.getCenter(target),
    buttons: kSecondaryButton,
  );
  await g.up();
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, Finder row, String item) async {
  await _rightClick(tester, row);
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

/// The local branch row named [name]: the first match, above the remotes.
Finder _local(String name) => find.text(name).first;
Finder _remote(String name) => find.text(name).last;

void main() {
  testWidgets('a local branch can be hidden and shown again', (tester) async {
    final c = await _pumpSidebar(tester);

    await _pick(tester, _local('feat'), 'Hide in graph');
    expect(c.read(graphRefFilterProvider('/r')).valueOrNull?.hidden, {
      'refs/heads/feat',
    });
    expect(find.byTooltip('Hidden in the graph'), findsOneWidget);
    // Dimmed, so a glance down the list shows what the graph leaves out.
    expect(
      tester.widget<Text>(_local('feat')).style!.color,
      AppTokens.dark().textFaint,
    );

    await _pick(tester, _local('feat'), 'Show in graph');
    expect(
      c.read(graphRefFilterProvider('/r')).valueOrNull,
      GraphRefFilter.none,
    );
    expect(find.byTooltip('Hidden in the graph'), findsNothing);
  });

  testWidgets('a remote branch can be soloed and unsoloed', (tester) async {
    final c = await _pumpSidebar(tester);

    await _pick(tester, _remote('feat'), 'Solo in graph');
    expect(c.read(graphRefFilterProvider('/r')).valueOrNull?.solo, {
      'refs/remotes/origin/feat',
    });
    expect(find.byTooltip('Soloed in the graph'), findsOneWidget);

    await _pick(tester, _remote('feat'), 'Stop soloing');
    expect(
      c.read(graphRefFilterProvider('/r')).valueOrNull,
      GraphRefFilter.none,
    );
  });

  group('GraphRefFilterBar', () {
    Future<ProviderContainer> pumpBar(
      WidgetTester tester,
      GraphRefFilter filter,
    ) async {
      tester.view.physicalSize = const Size(900, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const GraphRefFilterBar(repoPath: '/r')));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(GraphRefFilterBar)),
      );
      final ctl = c.read(graphRefFilterProvider('/r').notifier);
      await c.read(graphRefFilterProvider('/r').future);
      for (final r in filter.hidden) {
        await ctl.toggleHidden(r);
      }
      for (final r in filter.solo) {
        await ctl.toggleSolo(r);
      }
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('shows nothing without a filter', (tester) async {
      await pumpBar(tester, GraphRefFilter.none);
      expect(find.text('Show all'), findsNothing);
    });

    testWidgets('names the soloed branches', (tester) async {
      await pumpBar(
        tester,
        const GraphRefFilter(
          solo: {'refs/heads/feat', 'refs/remotes/origin/main'},
        ),
      );
      expect(find.text('Graph shows only feat, origin/main'), findsOneWidget);
    });

    testWidgets('counts hidden branches, and Show all clears', (tester) async {
      final c = await pumpBar(
        tester,
        const GraphRefFilter(hidden: {'refs/heads/a', 'refs/heads/b'}),
      );
      expect(find.text('2 branches hidden from the graph'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(
        c.read(graphRefFilterProvider('/r')).valueOrNull,
        GraphRefFilter.none,
      );
      expect(find.text('Show all'), findsNothing);
    });
  });

  test('shortRefName drops the ref namespace', () {
    expect(shortRefName('refs/heads/feat/x'), 'feat/x');
    expect(shortRefName('refs/remotes/origin/main'), 'origin/main');
    expect(shortRefName('HEAD'), 'HEAD');
  });
}
