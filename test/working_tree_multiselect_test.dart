import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/working_selection.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
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

/// Records what the panel asks for instead of touching a repository.
class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  final calls = <String>[];

  @override
  Future<void> stageFile(String p) async => calls.add('stage $p');
  @override
  Future<void> unstageFile(String p) async => calls.add('unstage $p');
  @override
  Future<void> stageFiles(List<String> paths) async =>
      calls.add('stage ${paths.join(',')}');
  @override
  Future<void> unstageFiles(List<String> paths) async =>
      calls.add('unstage ${paths.join(',')}');
  @override
  Future<void> discardFiles(List<WorkingFile> files) async =>
      calls.add('discard ${files.map((f) => f.path).join(',')}');
}

const _data = RepoData(
  working: [
    WorkingFile(path: 'a.txt', worktree: GitChange.modified),
    WorkingFile(path: 'b.txt', worktree: GitChange.modified),
    WorkingFile(path: 'c.txt', worktree: GitChange.untracked),
    WorkingFile(path: 'd.txt', worktree: GitChange.modified),
    WorkingFile(path: 's1.txt', index: GitChange.modified),
    WorkingFile(path: 's2.txt', index: GitChange.added),
  ],
);

void main() {
  late _RecordingActions actions;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, {double width = 400}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
          gitServiceProvider.overrideWithValue(_FakeGit()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          repoActionsProvider.overrideWith(
            (ref, path) => actions = _RecordingActions(
              ref,
              path,
              GitWriter(_FakeGit(), path),
            ),
          ),
          repoDataProvider.overrideWith((ref, path) async => _data),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return WorkingTreePanel(repoPath: '/r', data: _data);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> modClick(
    WidgetTester tester,
    String text,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(key);
    await tester.tap(find.text(text));
    await tester.sendKeyUpEvent(key);
    await tester.pump();
  }

  Future<void> cmdClick(WidgetTester tester, String text) =>
      modClick(tester, text, LogicalKeyboardKey.metaLeft);

  /// A widget test on a desktop [platform], reset inside the body so a
  /// failing expect cannot leak the override into the next test.
  void desktopTest(
    String name,
    Future<void> Function(WidgetTester) body, {
    TargetPlatform platform = TargetPlatform.macOS,
  }) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  WorkingSelection selection() =>
      container.read(workingSelectionProvider('/r'));

  desktopTest('a plain click opens the file and picks only it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('b.txt'));
    await tester.pump();
    expect(container.read(diffTargetProvider)?.path, 'b.txt');
    expect(selection().paths, {'b.txt'});
    expect(find.byTooltip('Clear selection'), findsNothing);
  });

  desktopTest('Cmd-click adds files without opening them', (tester) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'd.txt');
    expect(container.read(diffTargetProvider), isNull);
    expect(selection().paths, {'a.txt', 'd.txt'});
    expect(find.text('2 selected'), findsOneWidget);
  });

  desktopTest('Ctrl-click is the toggle off macOS', (tester) async {
    await pump(tester);
    await modClick(tester, 'a.txt', LogicalKeyboardKey.controlLeft);
    await modClick(tester, 'b.txt', LogicalKeyboardKey.controlLeft);
    expect(selection().paths, {'a.txt', 'b.txt'});
  }, platform: TargetPlatform.linux);

  desktopTest('Cmd is not the toggle off macOS', (tester) async {
    await pump(tester);
    await tester.tap(find.text('a.txt'));
    await cmdClick(tester, 'b.txt');
    expect(selection().paths, {'b.txt'});
  }, platform: TargetPlatform.windows);

  desktopTest('Shift-click takes the run from the anchor', (tester) async {
    await pump(tester);
    await tester.tap(find.text('a.txt'));
    await modClick(tester, 'c.txt', LogicalKeyboardKey.shiftLeft);
    expect(selection().paths, {'a.txt', 'b.txt', 'c.txt'});
    expect(find.text('3 selected'), findsOneWidget);
  });

  desktopTest('the bar stages the selection in list order', (tester) async {
    await pump(tester);
    await cmdClick(tester, 'd.txt');
    await cmdClick(tester, 'a.txt');
    await tester.tap(find.widgetWithText(TextButton, 'Stage'));
    await tester.pump();
    expect(actions.calls, ['stage a.txt,d.txt']);
    expect(selection().isEmpty, isTrue);
  });

  desktopTest('in the staged list the bar unstages', (tester) async {
    await pump(tester);
    await cmdClick(tester, 's1.txt');
    await cmdClick(tester, 's2.txt');
    await tester.tap(find.widgetWithText(TextButton, 'Unstage'));
    await tester.pump();
    expect(actions.calls, ['unstage s1.txt,s2.txt']);
  });

  desktopTest('a selected row\'s checkbox acts on the whole selection', (
    tester,
  ) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'b.txt');
    final row = find.ancestor(
      of: find.text('b.txt'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    expect(actions.calls, ['stage a.txt,b.txt']);
  });

  desktopTest('an unselected row\'s checkbox still acts on that row', (
    tester,
  ) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'b.txt');
    final row = find.ancestor(
      of: find.text('d.txt'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    expect(actions.calls, ['stage d.txt']);
  });

  desktopTest('discarding the selection confirms first', (tester) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'c.txt');
    await tester.tap(find.byTooltip('Discard 2 files…'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes to 2 files?'), findsOneWidget);
    expect(actions.calls, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['discard a.txt,c.txt']);
  });

  desktopTest('cancelling the discard keeps files and selection', (
    tester,
  ) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'c.txt');
    await tester.tap(find.byTooltip('Discard 2 files…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(actions.calls, isEmpty);
    expect(selection().paths, {'a.txt', 'c.txt'});
  });

  desktopTest('stashing the selection opens the dialog on it', (tester) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'c.txt');
    await tester.tap(find.byTooltip('Stash 2 files…'));
    await tester.pumpAndSettle();
    expect(find.text('Stash changes'), findsOneWidget);
    // The untracked pick turned untracked files on, so it is listed.
    expect(
      find.descendant(
        of: find.byType(CheckboxListTile),
        matching: find.text('c.txt'),
      ),
      findsOneWidget,
    );
  });

  desktopTest('right-clicking a selected row offers the bulk actions', (
    tester,
  ) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'b.txt');
    await tester.tap(find.text('a.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Stage 2 files'), findsOneWidget);
    expect(find.text('Discard 2 files…'), findsOneWidget);
    expect(find.text('Stash 2 files…'), findsOneWidget);
    await tester.tap(find.text('Stage 2 files'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['stage a.txt,b.txt']);
  });

  desktopTest('right-clicking an unselected row keeps the file menu', (
    tester,
  ) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'b.txt');
    await tester.tap(find.text('d.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Stage 2 files'), findsNothing);
    expect(find.text('Discard changes'), findsOneWidget);
  });

  desktopTest('the clear button drops the selection', (tester) async {
    await pump(tester);
    await cmdClick(tester, 'a.txt');
    await cmdClick(tester, 'b.txt');
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    expect(selection().isEmpty, isTrue);
    expect(find.text('2 selected'), findsNothing);
  });

  test('Shift runs follow the drawn order: path order, or folders first', () {
    const files = [
      WorkingFile(path: 'z.txt', worktree: GitChange.modified),
      WorkingFile(path: 'src/b.txt', worktree: GitChange.modified),
      WorkingFile(path: 'src/a.txt', worktree: GitChange.modified),
    ];
    expect(displayOrder(files, tree: false), [
      'z.txt',
      'src/b.txt',
      'src/a.txt',
    ]);
    expect(displayOrder(files, tree: true), [
      'src/a.txt',
      'src/b.txt',
      'z.txt',
    ]);
  });

  for (final width in [336.0, 400.0, 600.0]) {
    desktopTest('the bar fits at ${width}px', (tester) async {
      await pump(tester, width: width);
      await cmdClick(tester, 'a.txt');
      await cmdClick(tester, 'b.txt');
      expect(tester.takeException(), isNull);
      expect(find.text('2 selected'), findsOneWidget);
    });
  }
}
