import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/app_bottom_bar.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  final bool hasRemote;
  _FakeGit({this.hasRemote = true});

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    final out = switch (args.first) {
      'remote' when args.length == 1 => hasRemote ? 'origin\n' : '',
      'for-each-ref' => 'main\t*\t\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeGit git, {
  AppSettings settings = const AppSettings(),
}) async {
  final widget = ProviderScope(
    overrides: [
      gitServiceProvider.overrideWithValue(git),
      settingsProvider.overrideWith(
        (ref) => SettingsController(InMemorySettingsRepository(), settings),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppTokens.dark()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Align(child: AppBottomBar())),
    ),
  );
  await tester.pumpWidget(widget);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppBottomBar)),
  );
  container.read(workspaceProvider.notifier).openRepo('/r');
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Fetch menu runs git fetch for the chosen remote', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(tester, git);

    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch origin'));
    await tester.pumpAndSettle();

    expect(
      git.calls.any((c) => c.first == 'fetch' && c.contains('origin')),
      isTrue,
    );
  });

  testWidgets('force-push asks for confirmation before pushing', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(tester, git);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Force-push (with lease)'));
    await tester.pumpAndSettle();

    // Confirm dialog is up; nothing pushed yet.
    expect(find.text('Force-push?'), findsOneWidget);
    expect(git.calls.any((c) => c.first == 'push'), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Force-push'));
    await tester.pumpAndSettle();
    expect(
      git.calls.any(
        (c) => c.first == 'push' && c.contains('--force-with-lease'),
      ),
      isTrue,
    );
  });

  testWidgets('with no remote the buttons are disabled and warn', (
    tester,
  ) async {
    final git = _FakeGit(hasRemote: false);
    final container = await _pump(tester, git);

    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();

    // No menu opened; a warning toast explains why.
    expect(find.text('Fetch origin'), findsNothing);
    expect(
      container.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
    expect(git.calls.any((c) => c.first == 'fetch'), isFalse);
  });

  testWidgets('Pull menu offers a fast-forward-only pull', (tester) async {
    final git = _FakeGit();
    await _pump(tester, git);

    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull (fast-forward only)'));
    await tester.pumpAndSettle();

    final pull = git.calls.firstWhere((c) => c.first == 'pull');
    expect(pull, contains('--ff-only'));
  });

  testWidgets('Pull autostashes while the preference is on', (tester) async {
    final git = _FakeGit();
    await _pump(tester, git);

    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull (rebase)'));
    await tester.pumpAndSettle();

    final pull = git.calls.firstWhere((c) => c.first == 'pull');
    expect(pull, containsAll(['--rebase', '--autostash']));
  });

  testWidgets('Pull leaves a dirty tree alone with autostash off', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(tester, git, settings: const AppSettings(pullAutostash: false));

    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    // The plain "Pull" item, below the button that carries the same label.
    await tester.tap(find.text('Pull').last);
    await tester.pumpAndSettle();

    final pull = git.calls.firstWhere((c) => c.first == 'pull');
    expect(pull, isNot(contains('--autostash')));
  });

  testWidgets('the plain Pull follows the rebase strategy preference', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(
      tester,
      git,
      settings: const AppSettings(pullStrategy: 'rebase'),
    );

    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull').last);
    await tester.pumpAndSettle();

    expect(
      git.calls.firstWhere((c) => c.first == 'pull'),
      contains('--rebase'),
    );
  });

  testWidgets('the other strategy stays one click away', (tester) async {
    final git = _FakeGit();
    await _pump(
      tester,
      git,
      settings: const AppSettings(pullStrategy: 'rebase'),
    );

    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    // Preference is rebase, so the explicit escape hatch is a merge pull.
    await tester.tap(find.text('Pull (merge)'));
    await tester.pumpAndSettle();

    final pull = git.calls.firstWhere((c) => c.first == 'pull');
    expect(pull, isNot(contains('--rebase')));
  });

  testWidgets('pulling every remote follows the preference too', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(
      tester,
      git,
      settings: const AppSettings(pullStrategy: 'rebase'),
    );

    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull (all remotes)'));
    await tester.pumpAndSettle();

    expect(
      git.calls.firstWhere((c) => c.first == 'pull'),
      contains('--rebase'),
    );
  });
}
