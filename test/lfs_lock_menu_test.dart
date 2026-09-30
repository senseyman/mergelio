import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lfs.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

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

  List<List<String>> get lfsCalls =>
      calls.where((c) => c.first == 'lfs').toList();

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _mine = LfsLock(id: '5', path: 'a/mine.psd', owner: 'me');
const _theirs = LfsLock(id: '7', path: 'a/theirs.psd', owner: 'zed');

Future<_FakeGit> _pump(
  WidgetTester tester, {
  required WorkingFile file,
  bool isLfs = true,
  LfsLockState state = const LfsLockState(
    ours: [_mine],
    theirs: [_theirs],
    available: true,
    stale: false,
  ),
}) async {
  final git = _FakeGit();
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        lfsToolProvider.overrideWith((ref) async => '3.5.0'),
        lfsPathsProvider.overrideWith(
          (ref, q) async => isLfs ? {file.path} : const <String>{},
        ),
        lfsLocksProvider.overrideWith((ref, repo) async => state),
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
          body: WorkingTreePanel(
            repoPath: '/r',
            data: RepoData(working: [file]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return git;
}

// The panel's own lock list repeats some labels; menu entries are the items.
Finder _item(String label) => find.widgetWithText(PopupMenuItem<void>, label);

Future<void> _openMenu(WidgetTester tester, String path) async {
  await tester.tap(find.text(path.split('/').last), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

WorkingFile _wf(String p) => WorkingFile(path: p, worktree: GitChange.modified);

void main() {
  testWidgets('unlocked LFS file offers Lock file', (t) async {
    await _pump(t, file: _wf('a/free.psd'));
    await _openMenu(t, 'a/free.psd');
    expect(_item('Lock file'), findsOneWidget);
    expect(_item('Unlock file'), findsNothing);
    expect(_item('Force unlock…'), findsNothing);
  });

  testWidgets('Lock file runs lfs lock on that path', (t) async {
    final git = await _pump(t, file: _wf('a/free.psd'));
    await _openMenu(t, 'a/free.psd');
    await t.tap(_item('Lock file'));
    await t.pumpAndSettle();
    expect(git.lfsCalls.first, ['lfs', 'lock', '--json', '--', 'a/free.psd']);
  });

  testWidgets('own lock offers Unlock file', (t) async {
    final git = await _pump(t, file: _wf('a/mine.psd'));
    await _openMenu(t, 'a/mine.psd');
    expect(_item('Lock file'), findsNothing);
    expect(_item('Force unlock…'), findsNothing);
    await t.tap(_item('Unlock file'));
    await t.pumpAndSettle();
    expect(git.lfsCalls.first, ['lfs', 'unlock', '--json', '--id', '5']);
  });

  testWidgets('their lock offers Force unlock only', (t) async {
    await _pump(t, file: _wf('a/theirs.psd'));
    await _openMenu(t, 'a/theirs.psd');
    expect(_item('Force unlock…'), findsOneWidget);
    expect(_item('Lock file'), findsNothing);
    expect(_item('Unlock file'), findsNothing);
  });

  testWidgets('Force unlock then Cancel makes no unlock call', (t) async {
    final git = await _pump(t, file: _wf('a/theirs.psd'));
    await _openMenu(t, 'a/theirs.psd');
    await t.tap(_item('Force unlock…'));
    await t.pumpAndSettle();
    expect(find.text("Break someone else's lock"), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(git.lfsCalls.where((c) => c[1] == 'unlock'), isEmpty);
  });

  testWidgets('Force unlock then Confirm runs the forced unlock', (t) async {
    final git = await _pump(t, file: _wf('a/theirs.psd'));
    await _openMenu(t, 'a/theirs.psd');
    await t.tap(_item('Force unlock…'));
    await t.pumpAndSettle();
    await t.tap(find.text('Break lock'));
    await t.pumpAndSettle();
    expect(git.lfsCalls.first, [
      'lfs',
      'unlock',
      '--json',
      '--force',
      '--id',
      '7',
    ]);
  });

  testWidgets('not an LFS file: no lock items', (t) async {
    await _pump(t, file: _wf('a/free.txt'), isLfs: false);
    await _openMenu(t, 'a/free.txt');
    expect(find.text('Blame'), findsOneWidget);
    expect(_item('Lock file'), findsNothing);
  });

  testWidgets('locks unavailable: no lock items', (t) async {
    await _pump(t, file: _wf('a/free.psd'), state: LfsLockState.none);
    await _openMenu(t, 'a/free.psd');
    expect(find.text('Blame'), findsOneWidget);
    expect(_item('Lock file'), findsNothing);
  });

  testWidgets('dash-leading path gets no lock items', (t) async {
    await _pump(t, file: _wf('-x.psd'));
    await _openMenu(t, '-x.psd');
    expect(find.text('Blame'), findsOneWidget);
    expect(_item('Lock file'), findsNothing);
  });
}
