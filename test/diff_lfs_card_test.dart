import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lfs.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';
import 'package:mergelio/ui/diff/lfs_card.dart';

const _a = '4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393';
const _b = 'b7e2c1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2';

FileDiff _file({
  LfsPointer? before,
  LfsPointer? after,
  GitChange status = GitChange.modified,
}) => FileDiff(
  path: 'art.psd',
  status: status,
  lfs: LfsDiff(before: before, after: after),
);

Widget _app(
  Widget child, {
  String? tool = '3.5.1',
  Set<String> present = const {},
  List<Override> extra = const [],
  Locale? locale,
}) => ProviderScope(
  overrides: [
    lfsToolProvider.overrideWith((ref) async => tool),
    lfsObjectPresentProvider.overrideWith(
      (ref, key) async => present.contains(key.oid),
    ),
    ...extra,
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(body: child),
  ),
);

const _v = 'version https://git-lfs.github.com/spec/v1';

/// Serves a modified-pointer diff for lfs.psd; everything else is empty.
class _SheetGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'diff' && !args.contains('--cached')) {
      return const GitResult(0, '''
diff --git a/lfs.psd b/lfs.psd
--- a/lfs.psd
+++ b/lfs.psd
@@ -1,3 +1,3 @@
 $_v
-oid sha256:$_a
-size 4404019
+oid sha256:$_b
+size 5347738
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Serves a canned working-tree diff per path; any other path gets an empty
/// diff. `git diff -- <path>` ends with the path, so that picks the entry.
class _MultiFileGit implements GitService {
  final Map<String, String> diffs;
  _MultiFileGit(this.diffs);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'diff' && !args.contains('--cached')) {
      final body = diffs[args.last];
      if (body != null) return GitResult(0, body, '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  testWidgets('modified: title, both sizes, short oids, presence', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LfsCard(
          repoPath: '/r',
          file: _file(
            before: const LfsPointer(oid: _a, size: 4404019),
            after: const LfsPointer(oid: _b, size: 5347738),
          ),
        ),
        present: {_b},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LFS object'), findsOneWidget);
    expect(find.text('4.2 MB → 5.1 MB'), findsOneWidget);
    expect(find.textContaining(_a.substring(0, 12)), findsOneWidget);
    expect(find.textContaining(_b.substring(0, 12)), findsOneWidget);
    expect(find.text('Not downloaded'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.textContaining("git-lfs isn't installed"), findsNothing);
  });

  testWidgets('added and deleted show one size', (tester) async {
    await tester.pumpWidget(
      _app(
        LfsCard(
          repoPath: '/r',
          file: _file(
            after: const LfsPointer(oid: _a, size: 2048),
            status: GitChange.added,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Added LFS object'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        LfsCard(
          repoPath: '/r',
          file: _file(
            before: const LfsPointer(oid: _a, size: 2048),
            status: GitChange.deleted,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Deleted LFS object'), findsOneWidget);
  });

  testWidgets('moved in offers the text diff', (tester) async {
    var shown = false;
    await tester.pumpWidget(
      _app(
        LfsCard(
          repoPath: '/r',
          file: _file(after: const LfsPointer(oid: _a, size: 9)),
          onShowText: () => shown = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Moved into LFS'), findsOneWidget);
    await tester.tap(find.text('Show text diff'));
    expect(shown, isTrue);
  });

  testWidgets('moved out is labelled', (tester) async {
    await tester.pumpWidget(
      _app(
        LfsCard(
          repoPath: '/r',
          file: _file(before: const LfsPointer(oid: _a, size: 9)),
          onShowText: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Moved out of LFS'), findsOneWidget);
  });

  testWidgets('tool missing adds the explanation and the OS hint', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        _app(
          LfsCard(
            repoPath: '/r',
            file: _file(
              before: const LfsPointer(oid: _a, size: 1),
              after: const LfsPointer(oid: _b, size: 2),
            ),
          ),
          tool: null,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("git-lfs isn't installed"), findsOneWidget);
      expect(find.textContaining('git lfs install'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mismatch note: tracked path, no pointer', (tester) async {
    const target = DiffTarget(repoPath: '/r', path: 'art.psd', commitSha: 'c');
    Widget note(Set<String> tracked, List<FileDiff> files) => _app(
      const LfsMismatchNote(target: target),
      extra: [
        diffDocumentProvider.overrideWith(
          (ref, t) async =>
              DiffDoc(files: files, editable: false, staged: false),
        ),
        lfsPathsProvider.overrideWith((ref, q) async => tracked),
      ],
    );
    const plain = FileDiff(path: 'art.psd', status: GitChange.modified);
    await tester.pumpWidget(note({'art.psd'}, const [plain]));
    await tester.pumpAndSettle();
    expect(
      find.text('Tracked by LFS but stored as a regular blob'),
      findsOneWidget,
    );

    // Each provider family key below repeats across cases (same target),
    // so a family override only takes effect on a provider instance that
    // has not been read yet. Tearing down to an empty tree first disposes
    // the autoDispose family entries, so the next pump starts clean and
    // actually observes the new override.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(note(const {}, const [plain]));
    await tester.pumpAndSettle();
    expect(find.textContaining('regular blob'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      note({'art.psd'}, [_file(after: const LfsPointer(oid: _a, size: 1))]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('regular blob'), findsNothing);
  });

  testWidgets('mismatch note: an untracked file never has one', (tester) async {
    // An untracked file is diffed against nothing, outside git's filters, so
    // its plain diff says nothing about how it would be stored.
    const target = DiffTarget(repoPath: '/r', path: 'art.psd');
    const plain = FileDiff(path: 'art.psd', status: GitChange.added);
    await tester.pumpWidget(
      _app(
        const LfsMismatchNote(target: target),
        extra: [
          diffDocumentProvider.overrideWith(
            (ref, t) async =>
                const DiffDoc(files: [plain], editable: true, staged: false),
          ),
          repoDataProvider.overrideWith(
            (ref, path) async => const RepoData(
              working: [
                WorkingFile(path: 'art.psd', worktree: GitChange.untracked),
              ],
            ),
          ),
          lfsPathsProvider.overrideWith((ref, q) async => {'art.psd'}),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('regular blob'), findsNothing);
  });

  testWidgets('mismatch note shares the working-tree panel\'s lookup', (
    tester,
  ) async {
    // The panel already asked about every changed path; the note asking
    // about one of them under a different key would run check-attr again.
    const target = DiffTarget(repoPath: '/r', path: 'notes.csv');
    const plain = FileDiff(path: 'notes.csv', status: GitChange.modified);
    const working = [
      WorkingFile(path: 'notes.csv', worktree: GitChange.modified),
      WorkingFile(path: 'art.psd', worktree: GitChange.modified),
    ];
    final seen = <LfsQuery>[];
    await tester.pumpWidget(
      _app(
        const LfsMismatchNote(target: target),
        extra: [
          diffDocumentProvider.overrideWith(
            (ref, t) async =>
                const DiffDoc(files: [plain], editable: true, staged: false),
          ),
          repoDataProvider.overrideWith(
            (ref, path) async => const RepoData(working: working),
          ),
          lfsPathsProvider.overrideWith((ref, q) async {
            seen.add(q);
            return const <String>{};
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(seen.toSet(), {workingTreeLfsQuery('/r', working)});
  });

  testWidgets('card scrolls rather than overflowing a short sheet', (
    tester,
  ) async {
    // Its tallest form, in the longer locale, in a sheet dragged low.
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 120,
          child: LfsCard(
            repoPath: '/r',
            file: _file(after: const LfsPointer(oid: _a, size: 9)),
            onShowText: () {},
          ),
        ),
        tool: null,
        locale: const Locale('uk'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('diff sheet renders the card, not pointer lines', (tester) async {
    tester.view.physicalSize = const Size(1600, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_SheetGit()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          lfsToolProvider.overrideWith((ref) async => '3.5.1'),
          lfsObjectPresentProvider.overrideWith((ref, k) async => false),
          lfsPathsProvider.overrideWith((ref, q) async => {'lfs.psd'}),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
          ),
        ),
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(DiffSheet)));
    c.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: 'lfs.psd',
    );
    await tester.pumpAndSettle();
    expect(find.text('LFS object'), findsOneWidget);
    expect(find.text('4.2 MB → 5.1 MB'), findsOneWidget);
    expect(find.textContaining('oid sha256:'), findsNothing);
    // A pointer diff is not a mismatch.
    expect(find.textContaining('regular blob'), findsNothing);
    // Editing would put hand-written pointer text in the working tree, one
    // Stage away from being committed; the card offers no way to do that.
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Stage file').hitTestable(), findsOneWidget);
  });

  testWidgets('narrow header keeps the mismatch note from overflowing the '
      'Row', (tester) async {
    const path = 'tracked.psd';
    // 600px: narrow enough that the unwrapped note (~230px of English text,
    // longer in Ukrainian) overflows the Row once the Edit/Stage/Split/close
    // controls are also present, but wide enough that the header fits when
    // the note itself is absent — isolating this bug from the header's
    // separate, pre-existing overflow below ~530px.
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(
            _MultiFileGit({
              path:
                  '''
diff --git a/$path b/$path
--- a/$path
+++ b/$path
@@ -1,2 +1,2 @@
-old binary-ish content that is not a git-lfs pointer at all
+new binary-ish content that is not a git-lfs pointer at all
''',
            }),
          ),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          lfsToolProvider.overrideWith((ref) async => '3.5.1'),
          lfsObjectPresentProvider.overrideWith((ref, k) async => false),
          lfsPathsProvider.overrideWith((ref, q) async => {path}),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
          ),
        ),
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(DiffSheet)));
    c.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: path,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Tracked by LFS but stored as a regular blob'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching away from and back to a moved-into-LFS file resets '
      'the text-diff flag', (tester) async {
    const mCsv = 'm.csv';
    const pPsd = 'p.psd';
    final git = _MultiFileGit({
      mCsv:
          '''
diff --git a/$mCsv b/$mCsv
--- a/$mCsv
+++ b/$mCsv
@@ -1,3 +1,3 @@
-name,value
-a,1
-b,2
+$_v
+oid sha256:$_a
+size 9
''',
      pPsd:
          '''
diff --git a/$pPsd b/$pPsd
--- a/$pPsd
+++ b/$pPsd
@@ -1,3 +1,3 @@
 $_v
-oid sha256:$_a
-size 4404019
+oid sha256:$_b
+size 5347738
''',
    });
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
          lfsToolProvider.overrideWith((ref) async => '3.5.1'),
          lfsObjectPresentProvider.overrideWith((ref, k) async => false),
          lfsPathsProvider.overrideWith((ref, q) async => {mCsv, pPsd}),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
          ),
        ),
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(DiffSheet)));

    c.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: mCsv,
    );
    await tester.pumpAndSettle();
    expect(find.text('Moved into LFS'), findsOneWidget);

    await tester.tap(find.text('Show text diff'));
    await tester.pumpAndSettle();
    expect(find.text('Moved into LFS'), findsNothing);
    expect(find.textContaining('@@'), findsOneWidget);

    c.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: pPsd,
    );
    await tester.pumpAndSettle();
    expect(find.text('LFS object'), findsOneWidget);

    c.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: mCsv,
    );
    await tester.pumpAndSettle();
    expect(find.text('Moved into LFS'), findsOneWidget);
  });
}
