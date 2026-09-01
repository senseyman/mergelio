import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
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
  /// Pumps the Merge Tool over a session of [kind] for [branch], in [locale].
  Future<void> pumpSession(
    WidgetTester tester, {
    required MergeKind kind,
    required String branch,
    Locale locale = const Locale('en'),
  }) async {
    // flutter_test's fallback font draws every glyph a full em wide, so labels
    // measure far wider here than on screen. Give the header room rather than
    // let that artifact overflow the row.
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_FakeGit())],
    );
    addTearDown(container.dispose);
    container.read(mergeSessionProvider('/r').notifier).state = MergeSession(
      branch: branch,
      kind: kind,
      // One file with no hunks: MergeTool indexes files[0], so the list
      // must be non-empty; empty parts means "already resolved".
      files: const [ConflictFile(path: 'a.txt', parts: [])],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: MergeTool(repoPath: '/r')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('stash session header reads "Resolve conflicts"', (tester) async {
    await pumpSession(tester, kind: MergeKind.stash, branch: 'Stashed changes');

    expect(find.text('Resolve conflicts'), findsOneWidget);
    expect(find.textContaining('Merge'), findsNothing);
  });

  testWidgets('a cherry-pick session names the commit it paused on', (
    tester,
  ) async {
    await pumpSession(tester, kind: MergeKind.cherryPick, branch: 'abc1234');

    expect(find.text('Cherry-pick abc1234'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);
  });

  testWidgets('a revert session names the commit it paused on', (tester) async {
    await pumpSession(tester, kind: MergeKind.revert, branch: 'abc1234');

    expect(find.text('Revert abc1234'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);
  });

  testWidgets('the header translates with the locale', (tester) async {
    await pumpSession(
      tester,
      kind: MergeKind.revert,
      branch: 'abc1234',
      locale: const Locale('uk'),
    );

    expect(find.text('Відкотити abc1234'), findsOneWidget);
    expect(find.text('Вирішити'), findsOneWidget);
    expect(find.text('Перервати'), findsOneWidget);
  });
}
