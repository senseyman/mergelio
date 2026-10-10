import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/ignore.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/ignore_dialog.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppTokens.dark()]),
  home: Scaffold(body: home),
);

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpPanel(WidgetTester tester, WorkingFile file) async {
  _size(tester, 900);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
        gitServiceProvider.overrideWithValue(_FakeGit()),
        lfsToolProvider.overrideWith((ref) async => null),
        lfsPathsProvider.overrideWith((ref, q) async => const <String>{}),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
      child: _app(
        WorkingTreePanel(
          repoPath: '/r',
          data: RepoData(working: [file]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(file.path.split('/').last),
    buttons: kSecondaryButton,
  );
  await tester.pumpAndSettle();
}

/// Opens the dialog from a button and records what it returns.
Future<List<IgnoreChoice?>> _pumpDialog(
  WidgetTester tester, {
  required String path,
  String? nearestDir,
  double width = 900,
}) async {
  _size(tester, width);
  final results = <IgnoreChoice?>[];
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await showIgnoreDialog(context, path: path, nearestDir: nearestDir),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  group('context menu', () {
    testWidgets('offers Ignore… for an untracked file', (t) async {
      await _pumpPanel(
        t,
        const WorkingFile(path: 'logs/x.log', worktree: GitChange.untracked),
      );
      expect(find.text('Ignore…'), findsOneWidget);
    });

    testWidgets('does not offer it for a tracked file', (t) async {
      await _pumpPanel(
        t,
        const WorkingFile(path: 'logs/x.log', worktree: GitChange.modified),
      );
      expect(find.text('Blame'), findsOneWidget);
      expect(find.text('Ignore…'), findsNothing);
    });
  });

  group('dialog', () {
    testWidgets('previews each rule; defaults to this file at the root', (
      t,
    ) async {
      final results = await _pumpDialog(t, path: 'logs/x.log');
      expect(find.text('/logs/x.log'), findsOneWidget);
      expect(find.text('*.log'), findsOneWidget);
      expect(find.text('/logs/'), findsOneWidget);
      // No nested .gitignore, so no nearest choice.
      expect(find.textContaining('Nearest .gitignore'), findsNothing);

      await t.tap(find.text('Add rule'));
      await t.pumpAndSettle();
      expect(results.single?.scope, IgnoreScope.file);
      expect(results.single?.target, IgnoreTarget.root);
    });

    testWidgets('hides choices that have no rule', (t) async {
      await _pumpDialog(t, path: 'Makefile');
      expect(find.text('/Makefile'), findsOneWidget);
      expect(find.textContaining('Every'), findsNothing);
      expect(find.text('The whole folder'), findsNothing);
    });

    testWidgets('nearest target rewrites the previews relative to it', (
      t,
    ) async {
      final results = await _pumpDialog(
        t,
        path: 'pkg/gen/out.dart',
        nearestDir: 'pkg',
      );
      await t.tap(find.text('Nearest .gitignore (pkg/.gitignore)'));
      await t.pumpAndSettle();
      expect(find.text('/gen/out.dart'), findsOneWidget);
      expect(find.text('/gen/'), findsOneWidget);

      await t.tap(find.text('The whole folder'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add rule'));
      await t.pumpAndSettle();
      expect(results.single?.scope, IgnoreScope.folder);
      expect(results.single?.target, IgnoreTarget.nearest);
    });

    testWidgets('a folder pick that the new target cannot hold falls back', (
      t,
    ) async {
      final results = await _pumpDialog(
        t,
        path: 'pkg/out.dart',
        nearestDir: 'pkg',
      );
      await t.tap(find.text('The whole folder'));
      await t.pumpAndSettle();
      await t.tap(find.text('Nearest .gitignore (pkg/.gitignore)'));
      await t.pumpAndSettle();
      expect(find.text('The whole folder'), findsNothing);

      await t.tap(find.text('Add rule'));
      await t.pumpAndSettle();
      expect(results.single?.scope, IgnoreScope.file);
    });

    testWidgets('exclude target is offered with its hint', (t) async {
      final results = await _pumpDialog(t, path: 'x.log');
      expect(find.text('Only this clone; never committed'), findsOneWidget);
      await t.tap(find.text('.git/info/exclude'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add rule'));
      await t.pumpAndSettle();
      expect(results.single?.target, IgnoreTarget.exclude);
    });

    testWidgets('cancel returns nothing', (t) async {
      final results = await _pumpDialog(t, path: 'x.log');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(results.single, isNull);
    });

    testWidgets('long paths fit the narrowest window', (t) async {
      for (final width in [336.0, 480.0, 900.0]) {
        await _pumpDialog(
          t,
          path: 'a/very/deeply/nested/directory/tree/with/a/long_file_name.log',
          nearestDir: 'a/very/deeply/nested/directory',
          width: width,
        );
        expect(t.takeException(), isNull, reason: 'width $width');
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
      }
    });
  });
}
