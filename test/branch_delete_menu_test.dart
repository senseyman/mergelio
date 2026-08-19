// The two sidebar entry points for removing a branch on a remote: the
// remote-tracking row deletes it there and nowhere else, and a local branch
// that tracks one offers taking both away in a single confirmed step.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];

  Iterable<List<String>> callsTo(String command) =>
      calls.where((c) => c.first == command);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    // The two refs/heads reads differ by format: the tracking-aware one asks
    // for %(HEAD), the plain one only for short names.
    final tracking = args.any((a) => a.contains('%(HEAD)'));
    final out = switch (args.first) {
      'remote' when args.length == 1 => 'origin\n',
      'for-each-ref' when args.contains('refs/remotes') =>
        'origin/main\taaa\norigin/work\tbbb\norigin/release\tccc\n',
      'for-each-ref' when tracking =>
        'main\t*\t\taaa\torigin/main\n'
            'work\t\t\tbbb\torigin/work\n'
            'spike\t\t\tddd\t\n',
      'for-each-ref' => 'main\nwork\nspike\n',
      'rev-parse' => 'aaa\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  Future<_FakeGit> pumpSidebar(WidgetTester tester) async {
    final git = _FakeGit();
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
        ],
        child: MaterialApp(
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
    return git;
  }

  Future<void> openMenu(WidgetTester tester, Finder on) async {
    await tester.tap(on, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  testWidgets('a remote branch row offers deleting it on the remote', (
    tester,
  ) async {
    await pumpSidebar(tester);

    // `release` has no local counterpart, so the text is unique to the
    // remote-tracking row.
    await openMenu(tester, find.text('release'));

    expect(find.text('Delete origin/release…'), findsOneWidget);
  });

  testWidgets('deleting a remote branch asks first, then pushes the delete', (
    tester,
  ) async {
    final git = await pumpSidebar(tester);

    await openMenu(tester, find.text('release'));
    await tester.tap(find.text('Delete origin/release…'));
    await tester.pumpAndSettle();

    expect(find.text('Delete origin/release?'), findsOneWidget);
    await confirm(tester, 'Delete');

    expect(git.callsTo('push').single, [
      'push',
      'origin',
      '--delete',
      'release',
    ]);
  });

  testWidgets('cancelling the confirm leaves the remote branch alone', (
    tester,
  ) async {
    final git = await pumpSidebar(tester);

    await openMenu(tester, find.text('release'));
    await tester.tap(find.text('Delete origin/release…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(git.callsTo('push'), isEmpty);
  });

  testWidgets('a tracking branch offers deleting here and on the remote', (
    tester,
  ) async {
    await pumpSidebar(tester);

    // Branches come before Remotes in the sidebar, so the first `work` row is
    // the local branch.
    await openMenu(tester, find.text('work').first);

    expect(find.text('Delete branch'), findsOneWidget);
    expect(find.text('Delete branch and remote…'), findsOneWidget);
  });

  testWidgets('deleting both removes the local ref and pushes the delete', (
    tester,
  ) async {
    final git = await pumpSidebar(tester);

    await openMenu(tester, find.text('work').first);
    await tester.tap(find.text('Delete branch and remote…'));
    await tester.pumpAndSettle();

    expect(find.text('Delete work and origin/work?'), findsOneWidget);
    await confirm(tester, 'Delete both');

    expect(git.callsTo('branch').single, ['branch', '-d', 'work']);
  });

  testWidgets('an untracked branch offers only the local delete', (
    tester,
  ) async {
    await pumpSidebar(tester);

    // `spike` tracks nothing, so there is no remote half to offer.
    await openMenu(tester, find.text('spike'));

    expect(find.text('Delete branch'), findsOneWidget);
    expect(find.text('Delete branch and remote…'), findsNothing);
  });
}
