import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/ui/workspace/lfs_pointer_strip.dart';

class _Git implements GitService {
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
    if (args.first == 'config') return const GitResult(1, '', '');
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

Widget _app(
  _Git git,
  Set<String> pointers, {
  List<String> remotes = const ['origin'],
}) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(git),
    kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
    lfsPointerFilesProvider.overrideWith((ref, s) async => pointers),
    repoDataProvider.overrideWith((ref, p) async => RepoData(remotes: remotes)),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: const Scaffold(
      body: LfsPointerStrip(
        repoPath: '/r',
        working: [WorkingFile(path: 'a.bin', worktree: GitChange.modified)],
      ),
    ),
  ),
);

void main() {
  testWidgets('says how many files are still pointers and offers Download', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Git(), {'a.bin', 'b.bin'}));
    await tester.pumpAndSettle();
    expect(find.text('2 LFS files are not downloaded'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('with no remote it says so instead of offering Download', (
    tester,
  ) async {
    final git = _Git();
    await tester.pumpWidget(_app(git, {'a.bin'}, remotes: const []));
    await tester.pumpAndSettle();
    expect(find.text('1 LFS file is not downloaded'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
    expect(find.text('No remote to download from'), findsOneWidget);
  });

  testWidgets('shows nothing when no pointers remain', (tester) async {
    await tester.pumpWidget(_app(_Git(), {}));
    await tester.pumpAndSettle();
    expect(find.textContaining('LFS files'), findsNothing);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('Download runs lfs pull', (tester) async {
    final git = _Git();
    await tester.pumpWidget(_app(git, {'a.bin'}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(git.calls.where((c) => c.first == 'lfs').toList(), [
      ['lfs', 'pull'],
    ]);
  });
}
