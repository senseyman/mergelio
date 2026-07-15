import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/commit_details.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  Commit sig(String status) => Commit(
    sha: 'abcdef1234567890',
    message: 'm',
    author: 'A',
    authorEmail: 'a@e',
    date: DateTime(2026),
    signed: true,
    sigStatus: status,
  );

  Future<void> pump(WidgetTester tester, Commit c) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        commitFilesProvider((
          repo: '/r',
          sha: c.sha,
        )).overrideWith((ref) async => const <CommitFileChange>[]),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: CommitDetails(repoPath: '/r', commit: c, hasWip: false),
        ),
      ),
    ),
  );

  testWidgets('good signature reads Verified', (tester) async {
    await pump(tester, sig('G'));
    expect(find.text('Verified signature'), findsOneWidget);
  });

  testWidgets('bad signature is never labelled Verified', (tester) async {
    await pump(tester, sig('B'));
    expect(find.text('Bad signature'), findsOneWidget);
    expect(find.textContaining('Verified'), findsNothing);
  });

  testWidgets('expired signature is warned, not Verified', (tester) async {
    await pump(tester, sig('X'));
    expect(find.text('Expired signature'), findsOneWidget);
    expect(find.textContaining('Verified'), findsNothing);
  });

  testWidgets('untrusted-key (U) signature is not labelled Verified', (
    tester,
  ) async {
    await pump(tester, sig('U'));
    expect(find.text('Valid, untrusted key'), findsOneWidget);
    expect(find.textContaining('Verified'), findsNothing);
  });
}
