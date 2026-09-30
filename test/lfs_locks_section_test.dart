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
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/lfs_locks_section.dart';

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

LfsLock _lock(int i, String owner) => LfsLock(
  id: '$i',
  path: 'f$i.psd',
  owner: owner,
  lockedAt: DateTime.now().subtract(const Duration(hours: 3)),
);

LfsLockState _state({
  List<LfsLock> ours = const [],
  List<LfsLock> theirs = const [],
  bool available = true,
  bool stale = false,
}) => LfsLockState(
  ours: ours,
  theirs: theirs,
  available: available,
  stale: stale,
);

class _H {
  _H(this.git, this.container);
  final _FakeGit git;
  final ProviderContainer container;
}

Future<_H> _pump(
  WidgetTester tester,
  LfsLockState state, {
  List<WorkingFile> working = const [],
  Future<LfsLockState> Function()? loader,
}) async {
  final git = _FakeGit();
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        lfsLocksProvider.overrideWith(
          (ref, repo) async => loader != null ? loader() : state,
        ),
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
          body: LfsLocksSection(repoPath: '/r', working: working),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _H(
    git,
    ProviderScope.containerOf(tester.element(find.byType(LfsLocksSection))),
  );
}

void main() {
  testWidgets('hidden when locks are not available', (t) async {
    await _pump(t, LfsLockState.none);
    expect(find.text('Locks'), findsNothing);
  });

  testWidgets('shows Yours and Others groups with owners and ages', (t) async {
    await _pump(t, _state(ours: [_lock(1, 'me')], theirs: [_lock(2, 'zed')]));
    expect(find.text('Locks'), findsOneWidget);
    expect(find.text('Yours'), findsOneWidget);
    expect(find.text('Others'), findsOneWidget);
    expect(find.text('f1.psd'), findsOneWidget);
    expect(find.text('f2.psd'), findsOneWidget);
    expect(find.textContaining('zed'), findsOneWidget);
    expect(find.textContaining('3h'), findsWidgets);
  });

  testWidgets('a group with no locks is not shown', (t) async {
    await _pump(t, _state(theirs: [_lock(2, 'zed')]));
    expect(find.text('Yours'), findsNothing);
    expect(find.text('Others'), findsOneWidget);
  });

  testWidgets('Unlock on a yours row runs a plain unlock', (t) async {
    final h = await _pump(t, _state(ours: [_lock(1, 'me')]));
    await t.tap(find.text('Unlock file'));
    await t.pumpAndSettle();
    expect(h.git.lfsCalls.first, ['lfs', 'unlock', '--json', '--id', '1']);
  });

  testWidgets('Force unlock on an others row confirms, Cancel does nothing', (
    t,
  ) async {
    final h = await _pump(t, _state(theirs: [_lock(2, 'zed')]));
    await t.tap(find.text('Force unlock…'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(h.git.lfsCalls.where((c) => c[1] == 'unlock'), isEmpty);
  });

  testWidgets('Force unlock on an others row runs after Confirm', (t) async {
    final h = await _pump(t, _state(theirs: [_lock(2, 'zed')]));
    await t.tap(find.text('Force unlock…'));
    await t.pumpAndSettle();
    await t.tap(find.text('Break lock'));
    await t.pumpAndSettle();
    expect(h.git.lfsCalls.first, [
      'lfs',
      'unlock',
      '--json',
      '--force',
      '--id',
      '2',
    ]);
  });

  testWidgets('lists at most 100 rows, yours first, then "and N more"', (
    t,
  ) async {
    final ours = [for (var i = 0; i < 60; i++) _lock(i, 'me')];
    final theirs = [for (var i = 100; i < 150; i++) _lock(i, 'zed')];
    await _pump(t, _state(ours: ours, theirs: theirs));
    expect(find.text('Unlock file', skipOffstage: false), findsNWidgets(60));
    expect(find.text('Force unlock…', skipOffstage: false), findsNWidgets(40));
    expect(find.text('and 10 more', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a full server page reads as "N+" hidden', (t) async {
    final theirs = [for (var i = 0; i < 1000; i++) _lock(i, 'zed')];
    await _pump(t, _state(theirs: theirs));
    expect(find.text('and 900 more+', skipOffstage: false), findsOneWidget);
  });

  testWidgets('the list is height-capped', (t) async {
    await _pump(t, _state(ours: [for (var i = 0; i < 60; i++) _lock(i, 'me')]));
    expect(t.getSize(find.byType(LfsLocksSection)).height, lessThan(300));
  });

  testWidgets('a stale list says so', (t) async {
    await _pump(t, _state(ours: [_lock(1, 'me')], stale: true));
    expect(
      find.text("Couldn't refresh locks — showing the last known list"),
      findsOneWidget,
    );
  });

  testWidgets('a fresh list has no stale notice', (t) async {
    await _pump(t, _state(ours: [_lock(1, 'me')]));
    expect(find.textContaining("Couldn't refresh"), findsNothing);
  });

  testWidgets('Refresh bumps the LFS generation', (t) async {
    final h = await _pump(t, _state(ours: [_lock(1, 'me')]));
    expect(h.container.read(lfsGenerationProvider('/r')), 0);
    await t.tap(find.byTooltip('Refresh'));
    await t.pumpAndSettle();
    expect(h.container.read(lfsGenerationProvider('/r')), 1);
  });

  testWidgets('shows a progress indicator, not nothing, while refreshing', (
    t,
  ) async {
    final h = await _pump(t, _state(ours: [_lock(1, 'me')]));
    h.container.read(lfsGenerationProvider('/r').notifier).state++;
    await t.pump();
    expect(find.text('Locks'), findsOneWidget);
    expect(find.text('f1.psd'), findsOneWidget);
  });

  testWidgets('the unsupported flag flip toasts once across rebuilds', (
    t,
  ) async {
    final h = await _pump(t, _state(ours: [_lock(1, 'me')]));
    final flag = h.container.read(lfsLocksUnsupportedProvider('/r').notifier);
    flag.state = true;
    await t.pump();
    // Force rebuilds without another flip.
    h.container.read(lfsGenerationProvider('/r').notifier).state++;
    await t.pumpAndSettle();
    h.container.read(lfsGenerationProvider('/r').notifier).state++;
    await t.pumpAndSettle();
    final toasts = h.container
        .read(toastProvider)
        .where(
          (x) =>
              x.title == "This repository's server doesn't support file locks.",
        );
    expect(toasts, hasLength(1));
    expect(toasts.single.kind, ToastKind.info);
    // Let the toast timer finish.
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('a hidden section still toasts the flag flip', (t) async {
    final h = await _pump(t, LfsLockState.none);
    h.container.read(lfsLocksUnsupportedProvider('/r').notifier).state = true;
    await t.pump();
    expect(
      h.container.read(toastProvider).map((x) => x.title),
      contains("This repository's server doesn't support file locks."),
    );
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('tapping a row opens its diff when the file is changed', (
    t,
  ) async {
    final h = await _pump(
      t,
      _state(ours: [_lock(1, 'me')]),
      working: const [
        WorkingFile(path: 'f1.psd', worktree: GitChange.modified),
      ],
    );
    await t.tap(find.text('f1.psd'));
    await t.pumpAndSettle();
    final target = h.container.read(diffTargetProvider);
    expect(target?.path, 'f1.psd');
    expect(target?.staged, isFalse);
  });

  testWidgets('tapping a row for a file not in the working tree does nothing', (
    t,
  ) async {
    final h = await _pump(t, _state(ours: [_lock(1, 'me')]));
    await t.tap(find.text('f1.psd'));
    await t.pumpAndSettle();
    expect(h.container.read(diffTargetProvider), isNull);
  });
}
