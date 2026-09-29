import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/app_bottom_bar.dart';
import 'package:mergelio/ui/shell/global_actions.dart';

class _FakeGit implements GitService {
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
    return GitResult(0, args.first == 'remote' ? 'origin\n' : '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _pull = 'Pull LFS files';
const _fetchAll = 'Fetch all LFS objects';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeGit git, {
  required bool ready,
  Widget home = const Scaffold(body: Align(child: AppBottomBar())),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
        repoDataProvider('/r')
            .overrideWith((ref) async => const RepoData(remotes: ['origin'])),
        lfsReadyProvider.overrideWith((ref, s) async => ready),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  );
  container.read(workspaceProvider.notifier).openRepo('/r');
  container.read(repoDataProvider('/r'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('ready: Pull and Fetch menus offer the LFS entries', (
    tester,
  ) async {
    await _pump(tester, _FakeGit(), ready: true);
    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    expect(find.text(_pull), findsOneWidget);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();
    expect(find.text(_fetchAll), findsOneWidget);
  });

  testWidgets('not ready: neither menu offers an LFS entry', (tester) async {
    await _pump(tester, _FakeGit(), ready: false);
    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    expect(find.text(_pull), findsNothing);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();
    expect(find.text(_fetchAll), findsNothing);
  });

  testWidgets('Pull LFS files runs git lfs pull', (tester) async {
    final git = _FakeGit();
    await _pump(tester, git, ready: true);
    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_pull));
    await tester.pumpAndSettle();
    expect(
      git.calls.any((c) => c.length >= 2 && c[0] == 'lfs' && c[1] == 'pull'),
      isTrue,
    );
  });

  for (final ready in [true, false]) {
    testWidgets('palette LFS entries shown only when ready ($ready)', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        _FakeGit(),
        ready: ready,
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => openGlobalPalette(ctx, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      final src = workingTreeLfsSource('/r', const []);
      final sub = container.listen(lfsReadyProvider(src), (_, _) {});
      addTearDown(sub.close);
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(_pull), ready ? findsOneWidget : findsNothing);
      expect(find.text(_fetchAll), ready ? findsOneWidget : findsNothing);
    });
  }
}
