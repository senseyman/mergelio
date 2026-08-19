import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/ui/shell/remote_merge_confirm.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
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

/// Records fetches instead of reaching the network.
class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  final fetched = <String?>[];

  @override
  Future<void> fetch({String? remote, bool silent = false}) async {
    fetched.add(remote);
  }
}

void main() {
  // Stays null unless something reads the actions provider, which only the
  // fetch path does.
  _RecordingActions? actions;
  bool? outcome;

  Widget harness(String source) => ProviderScope(
    overrides: [
      gitServiceProvider.overrideWithValue(_FakeGit()),
      repoDataProvider.overrideWith(
        (ref, path) async => const RepoData(remotes: ['origin', 'upstream']),
      ),
      repoActionsProvider.overrideWith(
        (ref, path) =>
            actions = _RecordingActions(ref, path, GitWriter(_FakeGit(), path)),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppTokens.dark()]),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              outcome = await confirmRemoteSource(
                context,
                ref,
                repoPath: '/r',
                source: source,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );

  Future<void> start(WidgetTester tester, String source) async {
    outcome = null;
    actions = null;
    await tester.pumpWidget(harness(source));
    // Let repoData resolve so the remote list is known before the tap.
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('a local source merges without prompting', (tester) async {
    await start(tester, 'feature');
    expect(find.text('Merge from origin?'), findsNothing);
    expect(outcome, isTrue);
  });

  testWidgets('a branch merely containing a slash is still local', (
    tester,
  ) async {
    await start(tester, 'feature/origin');
    expect(outcome, isTrue);
  });

  testWidgets('a remote source prompts and can merge as-is', (tester) async {
    await start(tester, 'origin/main');
    expect(find.text('Merge from origin?'), findsOneWidget);

    await tester.tap(find.text('Merge as-is'));
    await tester.pumpAndSettle();

    expect(outcome, isTrue);
    expect(actions, isNull);
  });

  testWidgets('fetch and merge fetches the ref\'s own remote first', (
    tester,
  ) async {
    await start(tester, 'upstream/main');
    await tester.tap(find.text('Fetch and merge'));
    await tester.pumpAndSettle();

    expect(outcome, isTrue);
    expect(actions!.fetched, ['upstream']);
  });

  testWidgets('cancelling merges nothing', (tester) async {
    await start(tester, 'origin/main');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(outcome, isFalse);
    expect(actions, isNull);
  });
}
