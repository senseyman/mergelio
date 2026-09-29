import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/common/change_file_row.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

class _Git implements GitService {
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
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(_Git()),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(filesAsTree: false),
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('ChangeFileRow shows the chip only when lfs', (tester) async {
    const f = CommitFileChange(path: 'art.psd', change: GitChange.modified);
    await tester.pumpWidget(
      _app(ChangeFileRow(file: f, repoPath: '/r', onTap: () {}, lfs: true)),
    );
    expect(find.text('LFS'), findsOneWidget);
    expect(find.byTooltip('Stored with Git LFS'), findsOneWidget);

    await tester.pumpWidget(
      _app(ChangeFileRow(file: f, repoPath: '/r', onTap: () {})),
    );
    expect(find.text('LFS'), findsNothing);
  });

  testWidgets('working tree rows badge the paths LFS manages', (tester) async {
    await tester.pumpWidget(
      _app(
        const WorkingTreePanel(
          repoPath: '/r',
          data: RepoData(
            working: [
              WorkingFile(path: 'art.psd', worktree: GitChange.modified),
              WorkingFile(path: 'notes.txt', worktree: GitChange.modified),
            ],
          ),
        ),
        overrides: [
          lfsPathsProvider.overrideWith((ref, q) async => {'art.psd'}),
          lfsRepoProvider.overrideWith((ref, s) async => false),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LFS'), findsOneWidget);
    final chipRow = find.ancestor(
      of: find.text('LFS'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: chipRow.first, matching: find.text('art.psd')),
      findsOneWidget,
    );
  });

  testWidgets('working tree asks about every changed path once', (
    tester,
  ) async {
    final seen = <LfsQuery>[];
    await tester.pumpWidget(
      _app(
        const WorkingTreePanel(
          repoPath: '/r',
          data: RepoData(
            working: [
              WorkingFile(
                path: 'a.psd',
                index: GitChange.modified,
                worktree: GitChange.modified,
              ),
            ],
          ),
        ),
        overrides: [
          lfsPathsProvider.overrideWith((ref, q) async {
            seen.add(q);
            return const <String>{};
          }),
          lfsRepoProvider.overrideWith((ref, s) async => false),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(seen.map((q) => q.paths), [
      ['a.psd'],
    ]);
    expect(seen.single.source.rev, isNull);
  });

  testWidgets('working tree panel carries the banner', (tester) async {
    await tester.pumpWidget(
      _app(
        const WorkingTreePanel(
          repoPath: '/r',
          data: RepoData(
            working: [WorkingFile(path: 'a.psd', worktree: GitChange.modified)],
          ),
        ),
        overrides: [
          lfsRepoProvider.overrideWith((ref, s) async => true),
          lfsToolProvider.overrideWith((ref) async => null),
          lfsPathsProvider.overrideWith((ref, q) async => const <String>{}),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('stores files with Git LFS'), findsOneWidget);
  });
}
