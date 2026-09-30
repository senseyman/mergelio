import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/app_bottom_bar.dart';
import 'package:mergelio/ui/shell/global_actions.dart';
import 'package:mergelio/ui/shell/lfs_push_guard.dart';
import 'package:mergelio/ui/shell/repo_op_dialogs.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  int installExit = 0;

  /// Set once `git lfs install --local` has succeeded.
  bool installed = false;

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
    if (args.first == 'lfs' && args[1] == 'install') {
      installed = installExit == 0;
      return GitResult(installExit, '', installExit == 0 ? '' : 'no hooks dir');
    }
    final out = switch (args.first) {
      'remote' when args.length == 1 => 'origin\n',
      'for-each-ref' when args.contains('refs/heads') => 'main\t*\t\n',
      'rev-parse' => 'deadbeef\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

List<List<String>> _pushes(_FakeGit g) =>
    g.calls.where((c) => c.first == 'push').toList();

const _hookTitle = 'LFS hooks are not installed';

Widget _app(
  _FakeGit git,
  LfsPushReadiness readiness,
  Widget home, {
  RepoData? data,
  LfsPushReadiness afterInstall = LfsPushReadiness.ready,
}) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(git),
    lfsPushReadinessProvider.overrideWith(
      (ref, src) async => git.installed ? afterInstall : readiness,
    ),
    settingsProvider.overrideWith(
      (ref) => SettingsController(
        InMemorySettingsRepository(),
        const AppSettings(confirmDestructive: false),
      ),
    ),
    if (data != null) repoDataProvider('/r').overrideWith((ref) async => data),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: home,
  ),
);

Future<ProviderContainer> _open(WidgetTester tester, Finder host) async {
  final c = ProviderScope.containerOf(tester.element(host));
  c.read(workspaceProvider.notifier).openRepo('/r');
  await tester.pumpAndSettle();
  return c;
}

/// Calls the guard from a button and records its answer.
Future<List<bool>> _pumpGuard(
  WidgetTester tester,
  _FakeGit git,
  LfsPushReadiness readiness, {
  LfsPushReadiness afterInstall = LfsPushReadiness.ready,
}) async {
  final answers = <bool>[];
  await tester.pumpWidget(
    _app(
      git,
      readiness,
      afterInstall: afterInstall,
      Consumer(
        builder: (ctx, ref, _) => Scaffold(
          body: ElevatedButton(
            onPressed: () async =>
                answers.add(await confirmLfsPushReady(ctx, ref, '/r')),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  group('confirmLfsPushReady', () {
    testWidgets('ready: true, no dialog', (tester) async {
      final answers = await _pumpGuard(
        tester,
        _FakeGit(),
        LfsPushReadiness.ready,
      );
      expect(answers, [true]);
      expect(find.text(_hookTitle), findsNothing);
    });

    testWidgets('hookMissing: install runs lfs install --local', (
      tester,
    ) async {
      final git = _FakeGit();
      final answers = await _pumpGuard(
        tester,
        git,
        LfsPushReadiness.hookMissing,
      );
      expect(find.text(_hookTitle), findsOneWidget);
      await tester.tap(find.text('Install LFS hooks and push'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
      expect(
        git.calls.any((c) => c.join(' ') == 'lfs install --local'),
        isTrue,
      );
    });

    // git-lfs reports success yet leaves an existing pre-push hook that lacks
    // the execute bit as it is, and git skips such a hook on push.
    testWidgets('hookMissing: install that leaves the hook unrunnable returns '
        'false and says why', (tester) async {
      final git = _FakeGit();
      final answers = await _pumpGuard(
        tester,
        git,
        LfsPushReadiness.hookMissing,
        afterInstall: LfsPushReadiness.hookMissing,
      );
      await tester.tap(find.text('Install LFS hooks and push'));
      await tester.pumpAndSettle();
      expect(git.installed, isTrue);
      expect(answers, [false]);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      final errors = [
        for (final t in c.read(toastProvider))
          if (t.kind == ToastKind.error) '${t.title} ${t.description}',
      ];
      expect(errors, hasLength(1));
      expect(errors.single, contains('not executable'));
    });

    testWidgets('hookMissing: failed install returns false and toasts stderr', (
      tester,
    ) async {
      final git = _FakeGit()..installExit = 2;
      final answers = await _pumpGuard(
        tester,
        git,
        LfsPushReadiness.hookMissing,
      );
      await tester.tap(find.text('Install LFS hooks and push'));
      await tester.pumpAndSettle();
      expect(answers, [false]);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      expect(
        c
            .read(toastProvider)
            .any((t) => '${t.title} ${t.description}'.contains('no hooks dir')),
        isTrue,
      );
    });

    testWidgets('hookMissing: push anyway returns true without installing', (
      tester,
    ) async {
      final git = _FakeGit();
      final answers = await _pumpGuard(
        tester,
        git,
        LfsPushReadiness.hookMissing,
      );
      await tester.tap(find.text('Push anyway'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
      expect(git.calls.where((c) => c.first == 'lfs'), isEmpty);
    });

    testWidgets('hookMissing: cancel returns false', (tester) async {
      final answers = await _pumpGuard(
        tester,
        _FakeGit(),
        LfsPushReadiness.hookMissing,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answers, [false]);
    });

    testWidgets('toolMissing: only Push anyway and Cancel', (tester) async {
      final answers = await _pumpGuard(
        tester,
        _FakeGit(),
        LfsPushReadiness.toolMissing,
      );
      expect(find.text('git-lfs is not installed'), findsOneWidget);
      expect(find.text('Install LFS hooks and push'), findsNothing);
      await tester.tap(find.text('Push anyway'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });
  });

  group('every push entry point asks first and honours Cancel', () {
    Future<void> cancel(WidgetTester tester) async {
      expect(find.text(_hookTitle), findsOneWidget);
      // The push dialog underneath has a Cancel of its own; the guard's is on top.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
    }

    testWidgets('bottom bar Push', (tester) async {
      final git = _FakeGit();
      await tester.pumpWidget(
        _app(
          git,
          LfsPushReadiness.hookMissing,
          const Scaffold(body: Align(child: AppBottomBar())),
        ),
      );
      await _open(tester, find.byType(AppBottomBar));
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push origin'));
      await tester.pumpAndSettle();
      await cancel(tester);
      expect(_pushes(git), isEmpty);
    });

    testWidgets('bottom bar Force push', (tester) async {
      final git = _FakeGit();
      await tester.pumpWidget(
        _app(
          git,
          LfsPushReadiness.hookMissing,
          const Scaffold(body: Align(child: AppBottomBar())),
        ),
      );
      await _open(tester, find.byType(AppBottomBar));
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Force-push'));
      await tester.pumpAndSettle();
      await cancel(tester);
      expect(_pushes(git), isEmpty);
    });

    testWidgets('palette Push', (tester) async {
      final git = _FakeGit();
      await tester.pumpWidget(
        _app(
          git,
          LfsPushReadiness.hookMissing,
          Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () => openGlobalPalette(ctx, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await _open(tester, find.byType(Consumer));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      await cancel(tester);
      expect(_pushes(git), isEmpty);
    });

    testWidgets('push dialog submit', (tester) async {
      final git = _FakeGit();
      await tester.pumpWidget(
        _app(
          git,
          LfsPushReadiness.hookMissing,
          Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showPushDialog(ctx, ref, '/r'),
                child: const Text('open'),
              ),
            ),
          ),
          data: const RepoData(remotes: ['origin']),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Push'));
      await tester.pumpAndSettle();
      await cancel(tester);
      expect(_pushes(git), isEmpty);
    });

    testWidgets('sidebar Push tag', (tester) async {
      final git = _FakeGit();
      await tester.pumpWidget(
        _app(
          git,
          LfsPushReadiness.hookMissing,
          Scaffold(body: RepoSidebar(onCollapse: () {})),
          data: const RepoData(tags: ['v1'], remotes: ['origin']),
        ),
      );
      await _open(tester, find.byType(RepoSidebar));
      await tester.tap(find.text('v1'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push tag'));
      await tester.pumpAndSettle();
      await cancel(tester);
      expect(_pushes(git), isEmpty);
    });
  });
}
