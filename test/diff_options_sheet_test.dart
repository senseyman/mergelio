import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/diff_view_options.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

const _hunk = '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-old line
+new line
''';

/// Records every `git diff` it is asked for. With [whitespaceOnly] the change
/// vanishes as soon as whitespace is ignored, like a re-indent does.
class _FakeGit implements GitService {
  final bool whitespaceOnly;
  final diffs = <List<String>>[];
  _FakeGit({this.whitespaceOnly = false});

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'diff') {
      diffs.add(args);
      final ignoring =
          args.contains('--ignore-all-space') ||
          args.contains('--ignore-space-change');
      if (args.contains('--cached') || args.contains('--no-index')) {
        return const GitResult(0, '', '');
      }
      return GitResult(0, whitespaceOnly && ignoring ? '' : _hunk, '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakeGit git,
  DiffViewOptions options = const DiffViewOptions(),
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      gitServiceProvider.overrideWithValue(git),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
      diffViewOptionsProvider.overrideWith((_) => options),
    ],
  );
  addTearDown(container.dispose);
  container.read(diffTargetProvider.notifier).state = const DiffTarget(
    repoPath: '/r',
    path: 'a.txt',
  );
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
  return container;
}

void main() {
  testWidgets('showing whitespace offers hunk actions and no notice', (
    tester,
  ) async {
    await _pump(tester, git: _FakeGit());
    expect(find.text('Stage hunk'), findsWidgets);
    expect(find.textContaining('Whitespace is hidden'), findsNothing);
  });

  testWidgets('ignoring whitespace hides hunk actions and says why', (
    tester,
  ) async {
    await _pump(
      tester,
      git: _FakeGit(),
      options: const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
    );
    expect(find.text('new line'), findsOneWidget);
    expect(find.text('Stage hunk'), findsNothing);
    expect(find.text('Discard hunk'), findsNothing);
    expect(find.textContaining('Whitespace is hidden'), findsOneWidget);
    // Staging the whole file does not go through a patch, so it stays.
    expect(find.text('Stage file'), findsOneWidget);
  });

  testWidgets('showing whitespace keeps the per-line stage gutter', (
    tester,
  ) async {
    await _pump(tester, git: _FakeGit());
    expect(find.byIcon(Icons.add), findsWidgets);
  });

  testWidgets('ignoring whitespace also removes the per-line stage gutter', (
    tester,
  ) async {
    await _pump(
      tester,
      git: _FakeGit(),
      options: const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
    );
    expect(find.text('new line'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('re-picking the active options reads nothing again', (
    tester,
  ) async {
    final git = _FakeGit();
    final c = await _pump(tester, git: git);
    final before = git.diffs.length;
    final options = c.read(diffViewOptionsProvider);

    for (final label in ['Context: 3 lines', 'Show whitespace']) {
      await tester.tap(find.byTooltip('Diff options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(git.diffs.length, before);
    expect(identical(c.read(diffViewOptionsProvider), options), isTrue);
  });

  testWidgets('a whitespace-only change says so instead of "no changes"', (
    tester,
  ) async {
    await _pump(
      tester,
      git: _FakeGit(whitespaceOnly: true),
      options: const DiffViewOptions(whitespace: DiffWhitespace.ignoreChange),
    );
    expect(find.text('Only whitespace changed'), findsOneWidget);
    expect(find.textContaining('Whitespace is hidden'), findsNothing);
  });

  testWidgets('the options menu sets whitespace, re-reads and persists it', (
    tester,
  ) async {
    final git = _FakeGit();
    final c = await _pump(tester, git: git);
    await tester.tap(find.byTooltip('Diff options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignore all whitespace'));
    await tester.pumpAndSettle();

    expect(git.diffs.last, contains('--ignore-all-space'));
    expect(
      c.read(diffViewOptionsProvider).whitespace,
      DiffWhitespace.ignoreAll,
    );
    expect(c.read(settingsProvider).diffWhitespace, 'ignoreAll');
    expect(find.text('Stage hunk'), findsNothing);
  });

  testWidgets('a context choice leaves the whole-file view and persists', (
    tester,
  ) async {
    final git = _FakeGit();
    final c = await _pump(tester, git: git);
    c.read(diffTargetProvider.notifier).state = c
        .read(diffTargetProvider)!
        .withWholeFile(true);
    await tester.pumpAndSettle();
    expect(git.diffs.last, contains('-U$kWholeFileContext'));

    await tester.tap(find.byTooltip('Diff options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Context: 10 lines'));
    await tester.pumpAndSettle();

    expect(c.read(diffTargetProvider)!.wholeFile, isFalse);
    expect(git.diffs.last, contains('-U10'));
    expect(c.read(settingsProvider).diffContextLines, 10);
  });

  testWidgets('a narrow sheet folds the options into the overflow menu', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(tester, git: git, width: 336);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('More actions').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Context: 5 lines'));
    await tester.pumpAndSettle();
    expect(git.diffs.last, contains('-U5'));
  });
}
