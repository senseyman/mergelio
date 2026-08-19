// Right-clicking a navigator row. What the menu offers depends on the row, and
// each item routes to the filesystem or to git rather than doing the work here.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/project_ops.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/project_ops_provider.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/files/project_nav_panel.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
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

/// Records what git was asked to do instead of touching a repository.
class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  final staged = <String>[];
  final unstaged = <String>[];
  final discarded = <String>[];

  @override
  Future<void> stageFile(String p) async => staged.add(p);

  @override
  Future<void> unstageFile(String p) async => unstaged.add(p);

  @override
  Future<void> discardFile(WorkingFile f) async => discarded.add(f.path);
}

/// Records filesystem operations; the navigator never sees a real disk here.
class _RecordingOps extends ProjectOps {
  _RecordingOps(super.repoPath);

  final created = <String>[];
  final renamed = <String>[];
  final deleted = <String>[];

  /// Handed back by the next operation, so a refusal can be exercised too.
  ProjectOpResult? next;

  ProjectOpResult _result(String path) => next ?? ProjectOpResult.done(path);

  @override
  Future<ProjectOpResult> createFile(String relDir, String name) async {
    created.add(relDir.isEmpty ? name : '$relDir/$name');
    return _result(created.last);
  }

  @override
  Future<ProjectOpResult> createFolder(String relDir, String name) async {
    created.add(relDir.isEmpty ? name : '$relDir/$name');
    return _result(created.last);
  }

  @override
  Future<ProjectOpResult> rename(String relPath, String name) async {
    final cut = relPath.lastIndexOf('/');
    final to = cut < 0 ? name : '${relPath.substring(0, cut)}/$name';
    renamed.add('$relPath -> $to');
    return _result(to);
  }

  @override
  Future<ProjectOpResult> delete(String relPath) async {
    deleted.add(relPath);
    return _result(relPath);
  }
}

/// Root has lib/ and README.md; lib/ holds main.dart.
const _tree = {
  '': DirListing(
    entries: [
      DirEntry(name: 'lib', isDir: true),
      DirEntry(name: 'README.md', isDir: false),
    ],
  ),
  'lib': DirListing(entries: [DirEntry(name: 'main.dart', isDir: false)]),
};

const _modified = WorkingFile(path: 'README.md', worktree: GitChange.modified);

void main() {
  late _RecordingActions actions;
  late _RecordingOps ops;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Set<String> tracked = const {'README.md'},
    List<WorkingFile> working = const [_modified],
  }) async {
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
          dirListingProvider.overrideWith(
            (ref, DirKey key) async =>
                _tree[key.relDir] ?? const DirListing(error: 'missing'),
          ),
          ignoredInDirProvider.overrideWith(
            (ref, DirKey key) async => const {},
          ),
          trackedPathsProvider.overrideWith(
            (ref, String repo) async => tracked,
          ),
          repoDataProvider.overrideWith(
            (ref, String repo) async => RepoData(working: working),
          ),
          repoActionsProvider.overrideWith(
            (ref, path) => actions = _RecordingActions(
              ref,
              path,
              GitWriter(_FakeGit(), path),
            ),
          ),
          projectOpsProvider.overrideWith(
            (ref, path) => ops = _RecordingOps(path),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: ProjectNavPanel(repoPath: '/r'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProjectNavPanel)),
    );
    // Both are lazy; read them so a test that expects nothing to happen still
    // has a recorder to check.
    container
      ..read(projectOpsProvider('/r'))
      ..read(repoActionsProvider('/r'));
    return container;
  }

  Future<void> rightClick(WidgetTester tester, String label) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(label)),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String item) async {
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  /// Taps a dialog's confirming button. Looked up by widget type as well as
  /// label, since a dialog's title can read the same as its button.
  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  testWidgets('a folder offers the create items, a file does not', (
    tester,
  ) async {
    await pump(tester);

    await rightClick(tester, 'lib');
    expect(find.text('New file…'), findsOneWidget);
    expect(find.text('New folder…'), findsOneWidget);
    expect(find.text('Rename…'), findsOneWidget);

    await tester.tapAt(const Offset(5, 500));
    await tester.pumpAndSettle();

    await rightClick(tester, 'README.md');
    expect(find.text('New file…'), findsNothing);
    expect(find.text('Rename…'), findsOneWidget);
  });

  testWidgets('a modified file offers staging and discarding', (tester) async {
    await pump(tester);

    await rightClick(tester, 'README.md');

    expect(find.text('Stage'), findsOneWidget);
    expect(find.text('Unstage'), findsNothing);
    expect(find.text('Discard changes…'), findsOneWidget);
    expect(find.text('Show history'), findsOneWidget);
  });

  testWidgets('a clean file offers neither staging nor discarding', (
    tester,
  ) async {
    await pump(tester, working: const []);

    await rightClick(tester, 'README.md');

    expect(find.text('Stage'), findsNothing);
    expect(find.text('Discard changes…'), findsNothing);
    expect(find.text('Show history'), findsOneWidget);
  });

  testWidgets('a new file is created in the folder it was asked for', (
    tester,
  ) async {
    await pump(tester);

    await rightClick(tester, 'lib');
    await pick(tester, 'New file…');
    await type(tester, 'extra.dart');
    await confirm(tester, 'Create');

    expect(ops.created, ['lib/extra.dart']);
  });

  testWidgets('a newly created file is opened in an editor', (tester) async {
    final container = await pump(tester);

    await rightClick(tester, 'lib');
    await pick(tester, 'New file…');
    await type(tester, 'extra.dart');
    await confirm(tester, 'Create');

    expect(container.read(openFilesProvider('/r')).active, 'lib/extra.dart');
  });

  testWidgets('a new folder is created and left alone', (tester) async {
    final container = await pump(tester);

    await rightClick(tester, 'lib');
    await pick(tester, 'New folder…');
    await type(tester, 'ui');
    await confirm(tester, 'Create');

    expect(ops.created, ['lib/ui']);
    // A folder is not something an editor can show.
    expect(container.read(openFilesProvider('/r')).paths, isEmpty);
  });

  testWidgets('renaming moves the open editor tab with the file', (
    tester,
  ) async {
    final container = await pump(tester);
    container.read(openFilesProvider('/r').notifier).open('README.md');
    await tester.pumpAndSettle();

    await rightClick(tester, 'README.md');
    await pick(tester, 'Rename…');
    await type(tester, 'READ.md');
    await confirm(tester, 'Rename');

    expect(ops.renamed, ['README.md -> READ.md']);
    expect(container.read(openFilesProvider('/r')).paths, ['READ.md']);
  });

  testWidgets('a refused operation reports why and changes nothing', (
    tester,
  ) async {
    final container = await pump(tester);
    container.read(openFilesProvider('/r').notifier).open('README.md');
    await tester.pumpAndSettle();

    await rightClick(tester, 'README.md');
    await pick(tester, 'Rename…');
    ops.next = const ProjectOpResult.failed('READ.md already exists here');
    await type(tester, 'READ.md');
    await confirm(tester, 'Rename');

    expect(container.read(openFilesProvider('/r')).paths, ['README.md']);
    expect(
      container.read(toastProvider).single.title,
      'READ.md already exists here',
    );
    // Let the toast time out rather than leaving its timer behind.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('deleting asks first, then removes the file', (tester) async {
    await pump(tester);

    await rightClick(tester, 'README.md');
    await pick(tester, 'Delete…');
    expect(ops.deleted, isEmpty);

    await confirm(tester, 'Delete');

    expect(ops.deleted, ['README.md']);
  });

  testWidgets('cancelling the delete prompt leaves the file alone', (
    tester,
  ) async {
    await pump(tester);

    await rightClick(tester, 'README.md');
    await pick(tester, 'Delete…');
    await pick(tester, 'Cancel');

    expect(ops.deleted, isEmpty);
  });

  testWidgets('staging routes through the repository actions', (tester) async {
    await pump(tester);

    await rightClick(tester, 'README.md');
    await pick(tester, 'Stage');

    expect(actions.staged, ['README.md']);
  });

  testWidgets('unstaging is offered for what is in the index', (tester) async {
    await pump(
      tester,
      working: const [
        WorkingFile(path: 'README.md', index: GitChange.modified),
      ],
    );

    await rightClick(tester, 'README.md');
    await pick(tester, 'Unstage');

    expect(actions.unstaged, ['README.md']);
  });

  testWidgets('discarding asks first, then reverts the file', (tester) async {
    await pump(tester);

    await rightClick(tester, 'README.md');
    await pick(tester, 'Discard changes…');
    expect(actions.discarded, isEmpty);

    await confirm(tester, 'Discard');

    expect(actions.discarded, ['README.md']);
  });
}
