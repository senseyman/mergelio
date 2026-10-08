import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/commit_message.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/hooks.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/hooks.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

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
  Future<bool> isRepository(String path) async => true;
}

/// Records each commit and answers with whatever the test queued.
class _FakeActions implements RepoActions {
  final calls = <({String summary, bool noVerify})>[];
  CommitOutcome next = const CommitOutcome(committed: true);

  @override
  Future<CommitOutcome> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    bool noVerify = false,
    bool signoff = false,
    List<String> coauthors = const [],
    List<CommitTrailer> trailers = const [],
  }) async {
    calls.add((summary: summary, noVerify: noVerify));
    return next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _staged = WorkingFile(path: 'staged.txt', index: GitChange.modified);

Widget _harness(_FakeActions actions, {bool show = true}) => ProviderScope(
  overrides: [
    lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
    gitServiceProvider.overrideWithValue(_FakeGit()),
    repoActionsProvider.overrideWith((ref, path) => actions),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(
      body: show
          ? const WorkingTreePanel(
              repoPath: '/r',
              data: RepoData(working: [_staged]),
            )
          : const SizedBox(),
    ),
  ),
);

Finder get _summary => find.widgetWithText(TextField, 'Summary');

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(WorkingTreePanel)));

void main() {
  testWidgets('a hook rejection keeps the message and shows the hook output', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeActions()
      ..next = CommitOutcome(
        rejection: HookRejectedException(
          'pre-commit',
          const GitResult(1, '', 'lint: 3 problems'),
        ),
      );
    await tester.pumpWidget(_harness(actions));
    await tester.enterText(_summary, 'my message');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(
      find.text('The pre-commit hook rejected the commit'),
      findsOneWidget,
    );
    expect(find.text('Output from pre-commit'), findsOneWidget);
    expect(find.text('lint: 3 problems'), findsOneWidget);
    expect(find.text('Committed'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('my message'), findsOneWidget);
  });

  testWidgets('any other failure keeps the message too', (tester) async {
    final actions = _FakeActions()..next = const CommitOutcome();
    await tester.pumpWidget(_harness(actions));
    await tester.enterText(_summary, 'my message');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(find.text('my message'), findsOneWidget);
    expect(
      _container(tester).read(toastProvider).map((t) => t.title),
      isNot(contains('Committed')),
    );
  });

  testWidgets('skip hooks applies to one successful commit only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeActions();
    await tester.pumpWidget(_harness(actions));
    expect(find.text('Next commit skips hooks (--no-verify)'), findsNothing);

    await tester.tap(find.text('Skip hooks'));
    await tester.pump();
    expect(find.text('Next commit skips hooks (--no-verify)'), findsOneWidget);

    // A failed attempt leaves it armed and in view.
    actions.next = const CommitOutcome();
    await tester.enterText(_summary, 'one');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(actions.calls.last.noVerify, isTrue);
    expect(find.text('Next commit skips hooks (--no-verify)'), findsOneWidget);

    actions.next = const CommitOutcome(committed: true);
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(actions.calls.last.noVerify, isTrue);
    expect(find.text('Next commit skips hooks (--no-verify)'), findsNothing);
    expect(_container(tester).read(skipHooksOnceProvider('/r')), isFalse);

    await tester.enterText(_summary, 'two');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(actions.calls.last.noVerify, isFalse);
  });

  testWidgets('the rejection dialog can arm skip hooks', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeActions()
      ..next = CommitOutcome(
        rejection: HookRejectedException(
          'commit-msg',
          const GitResult(1, '', ''),
        ),
      );
    await tester.pumpWidget(_harness(actions));
    await tester.enterText(_summary, 'msg');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(find.text('The hook printed nothing.'), findsOneWidget);

    await tester.tap(find.text('Skip hooks for next commit'));
    await tester.pumpAndSettle();
    // Arming is all it does: nothing is committed until the user asks again.
    expect(actions.calls, hasLength(1));
    expect(find.text('Next commit skips hooks (--no-verify)'), findsOneWidget);
  });

  testWidgets('a hook --no-verify cannot skip is not offered as skippable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeActions()
      ..next = CommitOutcome(
        rejection: HookRejectedException(
          'prepare-commit-msg',
          const GitResult(1, '', 'no ticket'),
        ),
      );
    await tester.pumpWidget(_harness(actions));
    await tester.enterText(_summary, 'msg');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(
      find.text('The prepare-commit-msg hook rejected the commit'),
      findsOneWidget,
    );
    expect(find.text('Skip hooks for next commit'), findsNothing);
    expect(find.text('Manage hooks…'), findsOneWidget);
  });

  testWidgets('skip hooks does not outlive the composer', (tester) async {
    final actions = _FakeActions();
    await tester.pumpWidget(_harness(actions));
    await tester.tap(find.text('Skip hooks'));
    await tester.pump();
    expect(find.text('Next commit skips hooks (--no-verify)'), findsOneWidget);

    // Another tab replaces the composer; coming back finds hooks on again.
    await tester.pumpWidget(_harness(actions, show: false));
    await tester.pump();
    await tester.pumpWidget(_harness(actions));
    await tester.pump();
    expect(find.text('Next commit skips hooks (--no-verify)'), findsNothing);
  });

  testWidgets('a long transcript scrolls with the dialog, not inside it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeActions()
      ..next = CommitOutcome(
        rejection: HookRejectedException(
          'pre-commit',
          GitResult(1, '', List.generate(200, (i) => 'line $i').join('\n')),
        ),
      );
    await tester.pumpWidget(_harness(actions));
    await tester.enterText(_summary, 'msg');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    // SelectableText carries a Scrollable of its own, but with no line limit
    // it grows rather than scrolls; scroll views are what nest badly.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });
}
