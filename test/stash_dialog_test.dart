import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/ui/shell/repo_op_dialogs.dart';

/// Records every git call; succeeds with no output.
class _FakeGit implements GitService {
  final calls = <String>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args.join(' '));
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;

  List<String> get pushes => [
    for (final c in calls)
      if (c.startsWith('stash push')) c,
  ];
}

const _working = [
  WorkingFile(path: 'staged.txt', index: GitChange.modified),
  WorkingFile(path: 'edited.txt', worktree: GitChange.modified),
  WorkingFile(path: 'new.txt', worktree: GitChange.untracked),
];

Future<_FakeGit> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final git = _FakeGit();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        repoDataProvider.overrideWith(
          (ref, path) async => const RepoData(working: _working),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showStashDialog(context, ref, '/r'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return git;
}

Finder _stashButton() => find.widgetWithText(FilledButton, 'Stash');

void main() {
  testWidgets('lists tracked changes; untracked only once included', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('staged.txt'), findsOneWidget);
    expect(find.text('edited.txt'), findsOneWidget);
    expect(find.text('new.txt'), findsNothing);

    await tester.tap(find.text('Include untracked files'));
    await tester.pumpAndSettle();
    expect(find.text('new.txt'), findsOneWidget);
  });

  testWidgets('everything checked stashes without a pathspec', (tester) async {
    final git = await _open(tester);
    await tester.tap(_stashButton());
    await tester.pumpAndSettle();
    expect(git.pushes, ['stash push']);
  });

  testWidgets('unchecking a file stashes only the rest', (tester) async {
    final git = await _open(tester);
    await tester.tap(find.text('staged.txt'));
    await tester.pumpAndSettle();
    await tester.tap(_stashButton());
    await tester.pumpAndSettle();
    expect(git.pushes, ['stash push -- :(literal)edited.txt']);
  });

  testWidgets('keep-index and untracked are passed through', (tester) async {
    final git = await _open(tester);
    await tester.tap(find.text('Keep staged changes in place'));
    await tester.tap(find.text('Include untracked files'));
    await tester.pumpAndSettle();
    await tester.tap(_stashButton());
    await tester.pumpAndSettle();
    expect(git.pushes, ['stash push --keep-index --include-untracked']);
  });

  testWidgets('staged-only narrows the list and locks the other options', (
    tester,
  ) async {
    final git = await _open(tester);
    await tester.tap(find.text('Only staged changes'));
    await tester.pumpAndSettle();

    expect(find.text('staged.txt'), findsOneWidget);
    expect(find.text('edited.txt'), findsNothing);
    for (final label in [
      'Keep staged changes in place',
      'Include untracked files',
    ]) {
      final tile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, label),
      );
      expect(tile.onChanged, isNull, reason: label);
    }

    await tester.tap(_stashButton());
    await tester.pumpAndSettle();
    expect(git.pushes, ['stash push --staged']);
  });

  testWidgets('nothing selected cannot stash everything by accident', (
    tester,
  ) async {
    final git = await _open(tester);
    await tester.tap(find.text('staged.txt'));
    await tester.tap(find.text('edited.txt'));
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(_stashButton()).onPressed, isNull);
    await tester.tap(_stashButton());
    await tester.pumpAndSettle();
    expect(git.pushes, isEmpty);
  });
}
