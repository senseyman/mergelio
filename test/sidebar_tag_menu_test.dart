import 'package:flutter/gestures.dart';
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
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

/// Answers every git call without touching the host, recording argv and stdin.
class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  final List<String?> stdins = [];

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
    stdins.add(stdin);
    final out = switch (args.first) {
      'rev-parse' when args.contains('--abbrev-ref') => 'main\n',
      'rev-parse' => 'c0ffee\n',
      'for-each-ref' when args.contains('refs/heads') => 'main\t*\t\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

Widget _app(_FakeGit git) => ProviderScope(
  overrides: [
    lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
    gitServiceProvider.overrideWithValue(git),
    settingsProvider.overrideWith(
      (ref) => SettingsController(
        InMemorySettingsRepository(),
        const AppSettings(confirmDestructive: false),
      ),
    ),
    repoDataProvider('/r')
        .overrideWith((ref) async => const RepoData(tags: ['v1'])),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(body: RepoSidebar(onCollapse: () {})),
  ),
);

Future<void> _openMenu(WidgetTester tester, _FakeGit git) async {
  await tester.pumpWidget(_app(git));
  final c = ProviderScope.containerOf(tester.element(find.byType(RepoSidebar)));
  c.read(workspaceProvider.notifier).openRepo('/r');
  await tester.pumpAndSettle();
  await tester.tap(find.text('v1'), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.widgetWithText(FilledButton, 'OK'));
  await tester.pumpAndSettle();
}

bool _ran(_FakeGit git, List<String> argv) =>
    git.calls.any((c) => c.join('\u0000') == argv.join('\u0000'));

void main() {
  testWidgets('Checkout detaches at the tag by its full ref', (tester) async {
    final git = _FakeGit();
    await _openMenu(tester, git);

    await tester.tap(find.text('Checkout (detached HEAD)'));
    await tester.pumpAndSettle();

    expect(_ran(git, ['checkout', '--detach', 'refs/tags/v1']), isTrue);
  });

  testWidgets('Create branch from tag asks for a name and branches at the '
      'tagged commit', (tester) async {
    final git = _FakeGit();
    await _openMenu(tester, git);

    await tester.tap(find.text('Create branch from tag…'));
    await tester.pumpAndSettle();
    expect(find.text('Create branch'), findsOneWidget);
    await _answer(tester, 'fix');

    expect(_ran(git, ['branch', 'fix', 'c0ffee']), isTrue);
    // Branching is all it does: nothing is checked out.
    expect(git.calls.where((c) => c.first == 'checkout'), isEmpty);
  });

  testWidgets('Rename offers the current name and moves the tag', (
    tester,
  ) async {
    final git = _FakeGit();
    await _openMenu(tester, git);

    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    expect(find.text('Rename tag'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'v1'), findsOneWidget);
    await _answer(tester, 'v2');

    final i = git.calls.indexWhere((c) => c.first == 'update-ref');
    expect(i, isNot(-1));
    expect(git.stdins[i], contains('create refs/tags/v2 '));
    expect(git.stdins[i], contains('delete refs/tags/v1 '));
  });

  testWidgets('Rename to the same name does nothing', (tester) async {
    final git = _FakeGit();
    await _openMenu(tester, git);

    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await _answer(tester, 'v1');

    expect(git.calls.where((c) => c.first == 'update-ref'), isEmpty);
  });
}
