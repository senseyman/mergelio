import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

/// Serves a narrow diff by default and a whole-file one once `-U` widens the
/// context, so the sheet's expand toggle has two distinguishable states.
class _FakeGit implements GitService {
  final args = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> list, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    args.add(list);
    if (list.first != 'diff' || list.contains('--cached')) {
      return const GitResult(0, '', '');
    }
    final whole = list.any((a) => a.startsWith('-U'));
    return GitResult(
      0,
      whole
          ? '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,4 +1,4 @@
 first line
 keep
-old line
+new line
 last line
'''
          : '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -2,2 +2,2 @@
 keep
-old line
+new line
''',
      '',
    );
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _FakeGit git;

  Widget harness({List<Override> extra = const []}) => ProviderScope(
    overrides: [
      ...extra,
      gitServiceProvider.overrideWithValue(git),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [AppTokens.dark()]),
      home: const Scaffold(
        body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
      ),
    ),
  );

  Future<ProviderContainer> open(
    WidgetTester tester, {
    List<Override> extra = const [],
  }) async {
    await tester.pumpWidget(harness(extra: extra));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DiffSheet)),
    );
    container.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: 'a.txt',
    );
    await tester.pumpAndSettle();
    return container;
  }

  setUp(() => git = _FakeGit());

  testWidgets('expand toggle switches the target to the whole file', (
    tester,
  ) async {
    final c = await open(tester);
    expect(find.text('first line'), findsNothing);

    await tester.tap(find.byTooltip('Show whole file'));
    await tester.pumpAndSettle();

    expect(c.read(diffTargetProvider)!.wholeFile, isTrue);
    expect(find.text('first line'), findsOneWidget);
    expect(
      git.args.any(
        (a) => a.first == 'diff' && a.any((x) => x.startsWith('-U')),
      ),
      isTrue,
    );
  });

  testWidgets('collapsing goes back to the changed regions only', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.tap(find.byTooltip('Show whole file'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show changes only'));
    await tester.pumpAndSettle();

    expect(c.read(diffTargetProvider)!.wholeFile, isFalse);
    expect(find.text('first line'), findsNothing);
  });

  testWidgets('whole-file view hides hunk-level staging buttons', (
    tester,
  ) async {
    await open(tester);
    // The single hunk of a normal diff is a meaningful staging unit.
    expect(find.text('Stage hunk'), findsOneWidget);

    await tester.tap(find.byTooltip('Show whole file'));
    await tester.pumpAndSettle();

    // With the whole file as one hunk, "stage hunk" would stage everything.
    expect(find.text('Stage hunk'), findsNothing);
    expect(find.text('Discard hunk'), findsNothing);
  });

  testWidgets('expand toggle is hidden while editing', (tester) async {
    // The editor reads the file from disk, which a widget test has none of.
    final c = await open(
      tester,
      extra: [
        editableFileForPathProvider.overrideWith(
          (ref, FileRef _) async =>
              const EditableFile(text: 'keep\nold line\n'),
        ),
      ],
    );
    c.read(diffEditingProvider.notifier).state = c.read(diffTargetProvider);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show whole file'), findsNothing);
  });
}
