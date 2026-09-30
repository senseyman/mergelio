import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/shell/branch_drop.dart';

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

class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  bool behind = false;
  final calls = <String>[];

  @override
  Future<bool> isAncestor(String ancestor, String descendant) async => behind;
  @override
  Future<void> rebaseOnto(String source, String target) async =>
      calls.add('rebase $source $target');
  @override
  Future<void> mergeInto(String source, String target) async =>
      calls.add('merge $source $target');
  @override
  Future<void> fastForward(String target, String to) async =>
      calls.add('ff $target $to');
  @override
  Future<void> moveBranch(String name, String sha) async =>
      calls.add('move $name $sha');
  @override
  Future<void> resetHard(String sha) async => calls.add('hard $sha');
  @override
  Future<void> cherryPickOnto(String branch, String sha) async =>
      calls.add('pick $branch $sha');
}

const _sha = 'abcdef1234567890';

void main() {
  late _RecordingActions actions;

  /// Pumps a button that drops [source] on [target] when tapped, then taps it
  /// so the menu is open.
  Future<void> drop(
    WidgetTester tester,
    String source,
    BranchDropTarget target, {
    bool behind = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          repoDataProvider.overrideWith(
            (ref, path) async => const RepoData(
              branches: [
                Branch(name: 'main', current: true),
                Branch(name: 'feat'),
              ],
              remotes: ['origin'],
            ),
          ),
          repoActionsProvider.overrideWith(
            (ref, path) => actions = _RecordingActions(
              ref,
              path,
              GitWriter(_FakeGit(), path),
            )..behind = behind,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showBranchDropMenu(
                  context,
                  ref,
                  repoPath: '/r',
                  source: source,
                  target: target,
                  at: const Offset(100, 100),
                ),
                child: const Text('drop'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('drop'));
    await tester.pumpAndSettle();
  }

  testWidgets('a branch dropped on a commit rebases after confirming', (
    tester,
  ) async {
    await drop(tester, 'feat', const BranchDropTarget.commit(_sha));

    expect(find.text('Move «feat» to «abcdef1»'), findsOneWidget);
    expect(find.text('Cherry-pick «abcdef1» onto «feat»'), findsOneWidget);
    expect(find.text('Create branch here'), findsOneWidget);

    await tester.tap(find.text('Rebase «feat» onto «abcdef1»'));
    await tester.pumpAndSettle();
    expect(actions.calls, isEmpty, reason: 'nothing runs before the confirm');
    expect(
      find.text('Switches to «feat» and replays its commits onto «abcdef1».'),
      findsOneWidget,
    );

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['rebase feat $_sha']);
  });

  testWidgets('cancelling the confirm runs nothing', (tester) async {
    await drop(tester, 'feat', const BranchDropTarget.commit(_sha));
    await tester.tap(find.text('Move «feat» to «abcdef1»'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(actions.calls, isEmpty);
  });

  testWidgets('the current branch dropped on a branch offers resets and a '
      'fast-forward when the target is behind', (tester) async {
    await drop(
      tester,
      'main',
      const BranchDropTarget.branch('feat'),
      behind: true,
    );

    expect(find.text('Fast-forward «feat» to «main»'), findsOneWidget);
    expect(find.text('Reset «main» to «feat» (--soft)'), findsOneWidget);
    expect(find.text('Move «main» to «feat»'), findsNothing);

    await tester.tap(find.text('Reset «main» to «feat» (--hard)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['hard feat']);
  });

  testWidgets('fast-forward moves the target, not the dragged branch', (
    tester,
  ) async {
    await drop(
      tester,
      'main',
      const BranchDropTarget.branch('feat'),
      behind: true,
    );
    await tester.tap(find.text('Fast-forward «feat» to «main»'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['ff feat main']);
  });

  testWidgets('moving a branch onto a commit moves the dragged branch', (
    tester,
  ) async {
    await drop(tester, 'feat', const BranchDropTarget.commit(_sha));
    await tester.tap(find.text('Move «feat» to «abcdef1»'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['move feat $_sha']);
  });

  testWidgets('fast-forward is hidden when the target is not behind', (
    tester,
  ) async {
    await drop(tester, 'main', const BranchDropTarget.branch('feat'));
    expect(find.text('Fast-forward «feat» to «main»'), findsNothing);
  });

  testWidgets('a remote branch only merges or rebases', (tester) async {
    await drop(
      tester,
      'origin/feat',
      const BranchDropTarget.branch('main'),
      behind: true,
    );
    expect(find.byType(PopupMenuItem<BranchDrop>), findsNWidgets(2));
    expect(find.text('Merge «origin/feat» into «main»'), findsOneWidget);
    expect(find.text('Rebase «origin/feat» onto «main»'), findsOneWidget);
  });
}
