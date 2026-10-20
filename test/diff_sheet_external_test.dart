import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/external_tools.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

const _hunk = '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -4,2 +4,2 @@
 keep
-old line
+new line
''';

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
    // Every side and commit reads the same change, so the line the editor
    // gets depends only on which side is shown.
    if (args.first == 'diff' || args.first == 'show') {
      return const GitResult(0, _hunk, '');
    }
    if (args.first == 'config') {
      return const GitResult(0, 'diff.tool\nmeld\x00', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

class _Launcher implements ExternalLauncher {
  final calls = <(String, List<String>)>[];
  @override
  Future<ProcessResult> run(String executable, List<String> args) async {
    calls.add((executable, args));
    return ProcessResult(1, 0, '', '');
  }
}

/// The diff sheet hands its file to the editor, at the first change, and to
/// git's diff tool, from a menu of its own and from the narrow overflow menu.
void main() {
  late Directory dir;

  setUp(() {
    // Synchronous on purpose: widget tests cannot wait on real file I/O.
    dir = Directory.systemTemp.createTempSync('mergelio_dsx_');
    File('${dir.path}/a.txt').writeAsStringSync('x\n');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<(_FakeGit, _Launcher)> pump(
    WidgetTester tester,
    double width, {
    DiffTarget? target,
    List<WorkingFile> working = const [],
  }) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final git = _FakeGit();
    final launcher = _Launcher();
    final container = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        externalLauncherProvider.overrideWithValue(launcher),
        repoDataProvider.overrideWith(
          (ref, path) async => RepoData(working: working),
        ),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(editorCommand: 'ed +{line} {file}'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(diffTargetProvider.notifier).state =
        target ?? DiffTarget(repoPath: dir.path, path: 'a.txt');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(height: 500, child: DiffSheet(availableHeight: 500)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (git, launcher);
  }

  testWidgets('opens the editor at the first change', (tester) async {
    final (_, launcher) = await pump(tester, 1400);
    await tester.tap(find.byTooltip('Open in…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in editor'));
    await tester.pumpAndSettle();
    expect(launcher.calls.single.$1, 'ed');
    expect(launcher.calls.single.$2, ['+5', '${dir.path}/a.txt']);
  });

  testWidgets('opens git\'s diff tool on the side shown', (tester) async {
    final (git, _) = await pump(tester, 1400);
    await tester.tap(find.byTooltip('Open in…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in diff tool'));
    await tester.pumpAndSettle();
    expect(git.calls.where((c) => c.first == 'difftool').single, [
      'difftool',
      '--no-prompt',
      '--',
      'a.txt',
    ]);
  });

  testWidgets('a narrow sheet offers both from its overflow menu', (
    tester,
  ) async {
    final (_, launcher) = await pump(tester, 336);
    // The sheet's own menu comes first; hunk headers may have one too.
    await tester.tap(find.byTooltip('More actions').hitTestable().first);
    await tester.pumpAndSettle();
    Finder inMenu(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is PopupMenuItem),
      matching: find.text(label),
    );
    expect(inMenu('Open in diff tool'), findsOneWidget);
    await tester.tap(inMenu('Open in editor'));
    await tester.pumpAndSettle();
    expect(launcher.calls, hasLength(1));
  });

  testWidgets('an untracked file offers no diff tool', (tester) async {
    await pump(
      tester,
      1400,
      working: const [
        WorkingFile(path: 'a.txt', worktree: GitChange.untracked),
      ],
    );
    await tester.tap(find.byTooltip('Open in…'));
    await tester.pumpAndSettle();
    expect(find.text('Open in editor'), findsOneWidget);
    expect(find.text('Open in diff tool'), findsNothing);
  });

  // Line numbers on those sides are the index's or the commit's, not the
  // working-tree file's.
  for (final (name, staged, sha) in [
    ('the staged side', true, null),
    ('a commit', false, 'abc'),
  ]) {
    testWidgets('$name opens the editor at the top', (tester) async {
      final (_, launcher) = await pump(
        tester,
        1400,
        target: DiffTarget(
          repoPath: dir.path,
          path: 'a.txt',
          staged: staged,
          commitSha: sha,
        ),
      );
      await tester.tap(find.byTooltip('Open in…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open in editor'));
      await tester.pumpAndSettle();
      expect(launcher.calls.single.$2.first, '+1');
    });
  }
}
