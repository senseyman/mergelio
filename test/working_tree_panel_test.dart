import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

import 'support/refresh_counter.dart';

class _FakeGit implements GitService {
  final calls = <List<String>>[];
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// The git subcommand in [args], past any leading `-c key=value` pairs.
String? _subcommand(List<String> args) {
  var i = 0;
  while (i < args.length && args[i] == '-c') {
    i += 2;
  }
  return i < args.length ? args[i] : null;
}

const _staged = WorkingFile(path: 'staged.txt', index: GitChange.modified);
const _unstaged = WorkingFile(path: 'unstaged.txt', worktree: GitChange.added);
const _partial = WorkingFile(
  path: 'partial.txt',
  index: GitChange.modified,
  worktree: GitChange.modified,
);

Widget _harness(_FakeGit git, RepoData data, {Map<String, int>? refreshes}) =>
    ProviderScope(
      overrides: [
        if (refreshes != null) countRefreshes(refreshes),
        lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: WorkingTreePanel(repoPath: '/r', data: data),
        ),
      ),
    );

void main() {
  testWidgets('clean tree shows the empty state, no composer', (tester) async {
    await tester.pumpWidget(_harness(_FakeGit(), const RepoData()));
    expect(find.text('Working tree clean'), findsOneWidget);
    expect(find.text('Commit'), findsNothing);
  });

  testWidgets('lists staged and unstaged; a partial file shows in both', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _FakeGit(),
        const RepoData(working: [_staged, _unstaged, _partial]),
      ),
    );
    expect(find.text('STAGED (2)'), findsOneWidget); // staged + partial
    expect(find.text('UNSTAGED (2)'), findsOneWidget); // unstaged + partial
    expect(find.text('partial'), findsNWidgets(2));
  });

  testWidgets('tapping a file opens it in the diff target', (tester) async {
    await tester.pumpWidget(
      _harness(_FakeGit(), const RepoData(working: [_unstaged])),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    );
    await tester.tap(find.text('unstaged.txt'));
    await tester.pump();
    expect(container.read(diffTargetProvider)?.path, 'unstaged.txt');
  });

  testWidgets('empty summary is blocked with a warning, no git commit', (
    tester,
  ) async {
    final git = _FakeGit();
    await tester.pumpWidget(_harness(git, const RepoData(working: [_staged])));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Commit'));
    await tester.pump();

    expect(git.calls.any((c) => _subcommand(c) == 'commit'), isFalse);
    expect(
      container.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
  });

  testWidgets('a summary with staged changes runs git commit', (tester) async {
    final git = _FakeGit();
    await tester.pumpWidget(_harness(git, const RepoData(working: [_staged])));
    await tester.enterText(find.byType(TextField).first, 'my message');
    await tester.tap(find.widgetWithText(FilledButton, 'Commit'));
    await tester.pump();

    final commitCall = git.calls.firstWhere((c) => _subcommand(c) == 'commit');
    expect(commitCall, contains('my message'));
  });

  testWidgets('staged row opens the staged side', (tester) async {
    await tester.pumpWidget(
      _harness(_FakeGit(), const RepoData(working: [_staged])),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    );
    await tester.tap(find.text('staged.txt'));
    await tester.pump();
    expect(container.read(diffTargetProvider)?.staged, isTrue);
  });

  testWidgets('a staged rename opens with its old name, so the diff pairs '
      'the two', (tester) async {
    await tester.pumpWidget(
      _harness(
        _FakeGit(),
        const RepoData(
          working: [
            WorkingFile(
              path: 'new.png',
              origPath: 'old.png',
              index: GitChange.renamed,
            ),
          ],
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    );
    await tester.tap(find.textContaining('new.png').first);
    await tester.pump();
    expect(container.read(diffTargetProvider)?.origPath, 'old.png');
  });

  testWidgets('unstaged row opens the unstaged side', (tester) async {
    await tester.pumpWidget(
      _harness(_FakeGit(), const RepoData(working: [_unstaged])),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    );
    await tester.tap(find.text('unstaged.txt'));
    await tester.pump();
    expect(container.read(diffTargetProvider)?.staged, isFalse);
  });

  group('the refresh button', () {
    testWidgets('is there on a clean tree, where it matters most', (
      tester,
    ) async {
      final refreshes = <String, int>{};
      await tester.pumpWidget(
        _harness(_FakeGit(), const RepoData(), refreshes: refreshes),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Refresh (⌘R)'));
      await tester.pumpAndSettle();

      expect(refreshes, {'/r': 1});
    });

    testWidgets('is there beside the changes too', (tester) async {
      final refreshes = <String, int>{};
      await tester.pumpWidget(
        _harness(
          _FakeGit(),
          const RepoData(working: [_unstaged]),
          refreshes: refreshes,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Refresh (⌘R)'));
      await tester.pumpAndSettle();

      expect(refreshes, {'/r': 1});
    });
  });

  testWidgets('the header fits the narrowest right panel', (tester) async {
    // A clean tree: nothing below the header to overflow on its own.
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness(_FakeGit(), const RepoData()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Refresh (⌘R)').hitTestable(), findsOneWidget);
  });

  testWidgets('the header keeps its buttons inside the narrowest panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(_FakeGit(), const RepoData(working: [_unstaged])),
    );
    await tester.pumpAndSettle();
    // The composer's option row overflows here in the test font, which draws
    // every glyph a full em wide; that row is not what this test is about.
    tester.takeException();

    final refresh = tester.getRect(find.byTooltip('Refresh (⌘R)'));
    final discard = tester.getRect(find.byTooltip('Discard all changes'));
    final title = tester.getRect(find.text('CHANGES'));
    expect(title.right, lessThan(refresh.left));
    expect(refresh.right, lessThanOrEqualTo(discard.left));
    expect(discard.right, lessThan(300));
  });
}
