import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/repo_op_dialogs.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

/// A repository on `main` with a local `feature` branch and two remote-only
/// branches on `origin`.
class _FakeGit implements GitService {
  final List<List<String>> calls = [];

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
      'remote' when args.length == 1 => 'origin\n',
      'remote' when args.contains('get-url') => 'https://example.com/o.git\n',
      'for-each-ref' when args.contains('refs/heads') =>
        args.any((a) => a.contains('%(HEAD)'))
            ? 'main\t*\t\tsha1\torigin/main\nfeature\t\t\tsha2\t\n'
            : 'main\nfeature\n',
      'for-each-ref' when args.contains('refs/remotes') =>
        'origin/main\tsha1\norigin/release\tsha3\n',
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

Widget _scope(Widget home) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: home,
  ),
);

void main() {
  Future<void> pumpSidebar(WidgetTester tester) async {
    await tester.pumpWidget(
      _scope(Scaffold(body: RepoSidebar(onCollapse: () {}))),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RepoSidebar)),
    );
    container.read(workspaceProvider.notifier).openRepo('/r');
    await tester.pumpAndSettle();
  }

  group('merge dialog', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showMergeDialog(context, ref, '/r'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('cancelling the fetch prompt keeps the dialog open', (
      tester,
    ) async {
      await openDialog(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('origin/release').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      // Backing out of the fetch question returns to the branch picker rather
      // than throwing the whole dialog away.
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('lists remote-tracking branches alongside local ones', (
      tester,
    ) async {
      await openDialog(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // The current branch is not a merge source; everything else is.
      expect(find.text('feature'), findsWidgets);
      expect(find.text('origin/release'), findsWidgets);
      // origin/main is the current branch's own upstream, still mergeable.
      expect(find.text('origin/main'), findsWidgets);
    });
  });

  group('sidebar drag and drop', () {
    testWidgets('a remote branch row can be dragged onto a local branch', (
      tester,
    ) async {
      await pumpSidebar(tester);

      final source = find.text('release');
      final target = find.text('feature');
      expect(source, findsOneWidget);
      expect(target, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.text('Merge «origin/release» into «feature»'),
        findsOneWidget,
      );
    });

    testWidgets('a local branch can be dropped onto a remote branch row', (
      tester,
    ) async {
      await pumpSidebar(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('feature')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveTo(tester.getCenter(find.text('release')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // The merge lands on the local branch behind the remote ref, and the
      // menu says so rather than implying a merge into the remote itself.
      expect(find.text('Merge «feature» into «release»'), findsOneWidget);
      expect(
        find.text('Rebase «feature» onto «origin/release»'),
        findsOneWidget,
      );
    });
  });
}
