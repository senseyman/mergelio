import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/ui/merge/merge_tool.dart';

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

void main() {
  testWidgets('stash session header reads "Resolve conflicts"', (tester) async {
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_FakeGit())],
    );
    addTearDown(container.dispose);
    container
        .read(mergeSessionProvider('/r').notifier)
        .state = const MergeSession(
      branch: 'Stashed changes',
      kind: MergeKind.stash,
      // One file with no hunks: MergeTool indexes files[0], so the list
      // must be non-empty; empty parts means "already resolved".
      files: [ConflictFile(path: 'a.txt', parts: [])],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: MergeTool(repoPath: '/r')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Resolve conflicts'), findsOneWidget);
    expect(find.textContaining('Merge'), findsNothing);
  });
}
