import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

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

const _staged = WorkingFile(path: 'a.txt', index: GitChange.modified);

List<Override> _overrides({PendingOp? pending, String? execOutput}) => [
  rebaseExecOutputProvider('/r').overrideWith((ref) => execOutput),
  lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
  gitServiceProvider.overrideWithValue(_FakeGit()),
  pendingOpProvider('/r').overrideWith((ref) async => pending),
  settingsProvider.overrideWith(
    (ref) =>
        SettingsController(InMemorySettingsRepository(), const AppSettings()),
  ),
];

Widget _app(RepoData data) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppTokens.dark()]),
  home: Scaffold(
    body: WorkingTreePanel(repoPath: '/r', data: data),
  ),
);

Widget _harness(RepoData data, {PendingOp? pending, String? execOutput}) =>
    ProviderScope(
      overrides: _overrides(pending: pending, execOutput: execOutput),
      child: _app(data),
    );

/// The panel over a container the test can reach into.
Widget _harnessOn(ProviderContainer c, RepoData data) =>
    UncontrolledProviderScope(container: c, child: _app(data));

Finder _fieldWith(String text) =>
    find.byWidgetPredicate((w) => w is TextField && w.controller?.text == text);

void main() {
  Future<void> pumpStop(
    WidgetTester tester,
    RebaseStop stop, {
    String? out,
  }) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(
        const RepoData(),
        pending: PendingOp(kind: MergeKind.rebase, stop: stop),
        execOutput: out,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a break says so and still offers continue and abort', (
    tester,
  ) async {
    await pumpStop(tester, const RebaseStop.breakpoint());

    expect(find.textContaining('paused at a break'), findsOneWidget);
    expect(find.text('Continue rebase'), findsOneWidget);
    expect(find.text('Abort'), findsOneWidget);
  });

  testWidgets('a failed exec names its command', (tester) async {
    await pumpStop(tester, const RebaseStop.exec('flutter test'));

    expect(find.textContaining('flutter test'), findsOneWidget);
    expect(find.text('Continue rebase'), findsOneWidget);
  });

  testWidgets('the output of a failed exec can be read', (tester) async {
    await pumpStop(
      tester,
      const RebaseStop.exec('make'),
      out: 'FAIL: login_test',
    );

    expect(find.text('FAIL: login_test'), findsNothing);
    await tester.tap(find.text('Show output'));
    await tester.pumpAndSettle();
    expect(find.text('FAIL: login_test'), findsOneWidget);
  });

  testWidgets('a rejected reword is explained, its output readable', (
    tester,
  ) async {
    await pumpStop(tester, const RebaseStop.reword(), out: 'hook-says-no');

    expect(
      find.textContaining('message for a commit was rejected'),
      findsOneWidget,
    );
    expect(find.textContaining('printf'), findsNothing);
    await tester.tap(find.text('Show output'));
    await tester.pumpAndSettle();
    expect(find.text('hook-says-no'), findsOneWidget);
  });

  testWidgets('no output toggle when there is no output', (tester) async {
    await pumpStop(tester, const RebaseStop.exec('make'));
    expect(find.text('Show output'), findsNothing);
  });

  testWidgets('the composer stays open at a break so a fix can be committed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const RepoData(working: [_staged]),
        pending: const PendingOp(
          kind: MergeKind.rebase,
          stop: RebaseStop.breakpoint(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final commit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Commit'),
    );
    expect(commit.onPressed, isNotNull);
  });

  testWidgets('a prepared fixup message fills the composer', (tester) async {
    final c = ProviderContainer(overrides: _overrides());
    addTearDown(c.dispose);
    c.read(composerPrefillProvider('/r').notifier).state = 'fixup! Add login';
    await tester.pumpWidget(_harnessOn(c, const RepoData(working: [_staged])));
    await tester.pumpAndSettle();

    expect(_fieldWith('fixup! Add login'), findsOneWidget);
    // Taken up once, so it is not applied again on the next rebuild.
    expect(c.read(composerPrefillProvider('/r')), isNull);
  });

  testWidgets('a fixup prepared while the composer is open fills it too', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: _overrides());
    addTearDown(c.dispose);
    await tester.pumpWidget(_harnessOn(c, const RepoData(working: [_staged])));
    await tester.pumpAndSettle();
    c.read(composerPrefillProvider('/r').notifier).state = 'fixup! B';
    await tester.pumpAndSettle();

    expect(_fieldWith('fixup! B'), findsOneWidget);
  });
}
