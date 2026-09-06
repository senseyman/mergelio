import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/graph/graph_view.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async => const GitResult(0, '', '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> rightClick(WidgetTester tester, Finder at) async {
    final gesture = await tester.startGesture(
      tester.getCenter(at),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> pumpSidebar(WidgetTester tester) async {
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
          repoDataProvider('/r').overrideWith(
            (ref) async => const RepoData(
              branches: [Branch(name: 'feature')],
              remotes: ['origin'],
              remoteBranches: [RemoteBranch(remote: 'origin', branch: 'other')],
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(body: RepoSidebar(onCollapse: () {})),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RepoSidebar)),
    );
    container.read(workspaceProvider.notifier).openRepo('/r');
    await tester.pumpAndSettle();
  }

  testWidgets('a local branch menu copies the branch name', (tester) async {
    await pumpSidebar(tester);

    await rightClick(tester, find.text('feature'));
    expect(find.text('Copy name'), findsOneWidget);

    await tester.tap(find.text('Copy name'));
    await tester.pumpAndSettle();
    expect(clipboard, 'feature');
  });

  testWidgets('a remote branch menu copies the fully qualified name', (
    tester,
  ) async {
    await pumpSidebar(tester);

    await rightClick(tester, find.text('other'));
    expect(find.text('Copy name'), findsOneWidget);

    await tester.tap(find.text('Copy name'));
    await tester.pumpAndSettle();
    expect(clipboard, 'origin/other');
  });

  Future<void> pumpGraph(
    WidgetTester tester, {
    List<String> branches = const ['feature'],
  }) async {
    final workspace = WorkspaceController()..openRepo('/r');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith((ref) => workspace),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GraphList(
              data: RepoData(
                commits: assignLanes([
                  Commit(
                    sha: 'aaa',
                    message: 'msg aaa',
                    body: '',
                    author: 'Tester',
                    authorEmail: 't@e',
                    date: DateTime(2026, 7, 1),
                    parents: const [],
                    refs: [
                      for (final b in branches)
                        GitRef(name: b, kind: RefKind.local),
                    ],
                  ),
                ]),
                branches: [
                  for (final b in branches) Branch(name: b, tip: 'aaa'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a graph branch chip menu copies the branch name', (
    tester,
  ) async {
    await pumpGraph(tester);

    await rightClick(tester, find.text('feature'));
    expect(find.text('Copy name'), findsOneWidget);
    // The chip claims the click: the row's commit menu must not open too.
    expect(find.text('Copy SHA'), findsNothing);

    await tester.tap(find.text('Copy name'));
    await tester.pumpAndSettle();
    expect(clipboard, 'feature');
  });

  testWidgets('the overflow chip menu copies any branch it hides', (
    tester,
  ) async {
    // A row fits three chips, so four branches collapse the last two into +N.
    await pumpGraph(tester, branches: ['a', 'b', 'c', 'd']);
    expect(find.text('+2'), findsOneWidget);

    await rightClick(tester, find.text('+2'));

    expect(find.text('Copy «c»'), findsOneWidget);
    expect(find.text('Copy «d»'), findsOneWidget);
    expect(find.text('Copy «a»'), findsNothing);
    expect(find.text('Copy SHA'), findsNothing);

    await tester.tap(find.text('Copy «d»'));
    await tester.pumpAndSettle();
    expect(clipboard, 'd');
  });

  testWidgets('right-clicking the graph row still opens the commit menu', (
    tester,
  ) async {
    await pumpGraph(tester);

    await rightClick(tester, find.text('msg aaa'));

    expect(find.text('Copy SHA'), findsOneWidget);
    expect(find.text('Copy name'), findsNothing);
  });
}
