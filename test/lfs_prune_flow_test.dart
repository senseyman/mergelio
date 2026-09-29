import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/shell/lfs_prune_flow.dart';

class _FakeGit implements GitService {
  _FakeGit(this.dryRun);
  final GitResult dryRun;
  final List<List<String>> calls = [];

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
    if (args.length >= 2 && args[0] == 'lfs' && args[1] == 'prune') {
      return args.contains('--dry-run') ? dryRun : GitResult(0, '', '');
    }
    return GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;

  int get pruneCalls => calls
      .where(
        (c) =>
            c.length >= 2 &&
            c[0] == 'lfs' &&
            c[1] == 'prune' &&
            !c.contains('--dry-run'),
      )
      .length;
  int get lfsCalls => calls.where((c) => c.isNotEmpty && c[0] == 'lfs').length;
}

Future<ProviderContainer> _pump(WidgetTester tester, _FakeGit git) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(confirmDestructive: false),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showLfsPruneFlow(ctx, ref, '/r'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

List<String> _toasts(ProviderContainer c) => [
  for (final t in c.read(toastProvider)) t.title,
];

void main() {
  testWidgets('nothing to prune: toast, no prune', (tester) async {
    final git = _FakeGit(
      GitResult(0, '2 local objects, 2 retained, done.\n', ''),
    );
    final c = await _pump(tester, git);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(_toasts(c), contains('Nothing to prune'));
    expect(git.pruneCalls, 0);
  });

  testWidgets('unparseable output: toast, no prune', (tester) async {
    final git = _FakeGit(GitResult(0, 'weird\n', ''));
    final c = await _pump(tester, git);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(_toasts(c), contains('Could not preview the prune'));
    expect(git.pruneCalls, 0);
  });

  testWidgets('dry run failure: error toast, no dialog, no prune', (
    tester,
  ) async {
    final git = _FakeGit(GitResult(2, '', 'boom'));
    final c = await _pump(tester, git);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(c.read(toastProvider).any((t) => t.kind == ToastKind.error), isTrue);
    expect(find.text('Prune LFS objects'), findsNothing);
    expect(git.pruneCalls, 0);
  });

  testWidgets('something to prune: dialog names the count; cancel keeps all', (
    tester,
  ) async {
    final git = _FakeGit(
      GitResult(0, '3 local objects, 1 retained, done.\n', ''),
    );
    await _pump(tester, git);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Prune LFS objects'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(git.pruneCalls, 0);
  });

  testWidgets('confirm prunes exactly once', (tester) async {
    final git = _FakeGit(
      GitResult(0, '3 local objects, 1 retained, done.\n', ''),
    );
    await _pump(tester, git);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prune'));
    await tester.pumpAndSettle();
    expect(git.pruneCalls, 1);
  });

  testWidgets('busy repo lane: warning toast, no git lfs call', (tester) async {
    final git = _FakeGit(
      GitResult(0, '3 local objects, 1 retained, done.\n', ''),
    );
    final c = await _pump(tester, git);
    c.read(busyProvider.notifier).state = const BusyState('Something');
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(
      c.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
    expect(_toasts(c), isNot(contains('Could not preview the prune')));
    expect(git.lfsCalls, 0);
    expect(find.text('Prune LFS objects'), findsNothing);
  });
}
