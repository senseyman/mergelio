import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/review.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/review/review_picker.dart';

/// Resolves the refs the repository has and nothing else.
class _FakeGit implements GitService {
  static const known = {'main', 'feature', 'v1.0'};

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'rev-parse') {
      final rev = args.last.replaceAll('^{commit}', '');
      return known.contains(rev)
          ? GitResult(0, '${'a' * 40}\n', '')
          : const GitResult(1, '', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  Future<List<ReviewTarget?>> pump(
    WidgetTester tester, {
    List<Worktree> worktrees = const [],
  }) async {
    final results = <ReviewTarget?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          repoDataProvider.overrideWith(
            (ref, p) async => const RepoData(
              branches: [
                Branch(name: 'main'),
                Branch(name: 'feature', current: true),
              ],
              tags: ['v1.0'],
            ),
          ),
          worktreesProvider.overrideWith((ref, p) async => worktrees),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              // Nothing here has read the worktrees: the picker has to wait
              // for them itself.
              builder: (context, ref, _) {
                return TextButton(
                  onPressed: () async => results.add(
                    await showReviewPicker(context, ref, repoPath: '/r'),
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('starts from the current branch against the trunk', (
    tester,
  ) async {
    final results = await pump(tester);
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    expect(
      results.single,
      const ReviewTarget(repoPath: '/r', base: 'main', head: 'feature'),
    );
  });

  testWidgets('a side git cannot resolve is caught before opening', (
    tester,
  ) async {
    final results = await pump(tester);
    await tester.enterText(find.byType(TextField).last, 'nope');
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    expect(find.text('"nope" is not a commit in this repository'), findsOne);
    expect(results, isEmpty);

    await tester.enterText(find.byType(TextField).last, 'v1.0');
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    expect(results.single?.head, 'v1.0');
  });

  testWidgets('says what a worktree side leaves out, only when one exists', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('uncommitted edits'), findsNothing);
  });

  testWidgets('a linked worktree is offered with its note', (tester) async {
    await pump(
      tester,
      worktrees: const [Worktree(path: '/wt/hot', branch: 'hot')],
    );
    expect(find.textContaining('uncommitted edits'), findsOne);
  });
}
