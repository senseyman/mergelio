import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/shallow.dart';
import 'package:mergelio/ui/workspace/shallow_badge.dart';

class _FakeGit implements GitService {
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
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);
  int fetches = 0;

  @override
  Future<bool> fetchFullHistory() async {
    fetches++;
    return true;
  }
}

void main() {
  const repo = '/r';
  late _RecordingActions actions;
  late int reads;

  Future<void> pump(WidgetTester tester, List<bool> answers) async {
    reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          shallowRepoProvider.overrideWith(
            (ref, path) async =>
                answers[(reads++).clamp(0, answers.length - 1)],
          ),
          repoActionsProvider.overrideWith(
            (ref, path) => actions = _RecordingActions(
              ref,
              path,
              GitWriter(_FakeGit(), path),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: Center(child: ShallowBadge(path: repo)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('squeezed into a narrow row it ellipsizes, not overflows', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shallowRepoProvider.overrideWith((ref, path) async => true),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 40,
                child: Row(
                  children: [Flexible(child: ShallowBadge(path: repo))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ShallowBadge), findsOneWidget);
  });

  testWidgets('hidden for a full clone', (tester) async {
    await pump(tester, [false]);
    expect(find.text('SHALLOW'), findsNothing);
  });

  testWidgets('a shallow clone shows the pill; clicking deepens it', (
    tester,
  ) async {
    await pump(tester, [true, false]);
    expect(find.text('SHALLOW'), findsOneWidget);

    await tester.tap(find.text('SHALLOW'));
    await tester.pumpAndSettle();

    expect(actions.fetches, 1);
    // Re-read after the fetch, since a deepening fetch may move no ref.
    expect(find.text('SHALLOW'), findsNothing);
  });
}
