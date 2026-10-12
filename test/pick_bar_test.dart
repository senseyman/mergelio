import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/ui/graph/pick_bar.dart';

Commit _commit(String sha, {List<String> parents = const ['p']}) => Commit(
  sha: sha,
  message: 'subject $sha',
  author: 'Ada Lovelace',
  authorEmail: 'ada@example.com',
  date: DateTime(2026, 5, 1),
  parents: parents,
);

/// Never runs: the picks are recorded at the actions layer.
class _IdleGit implements GitService {
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
  Future<String> version() async => 'git version 2.55.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

class _PickActions extends RepoActions {
  final calls = <String>[];

  _PickActions(super.ref, super.path, super.writer);

  @override
  Future<void> cherryPickMany(
    List<String> shas, {
    bool noCommit = false,
  }) async => calls.add('${shas.join(' ')}${noCommit ? ' --no-commit' : ''}');
}

// Graph order: newest first.
final _commits = [_commit('ccc'), _commit('bbb'), _commit('aaa')];

Future<(ProviderContainer, _PickActions? Function())> _pump(
  WidgetTester tester, {
  required CommitPicks picks,
  List<Commit>? commits,
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _PickActions? actions;
  final container = ProviderContainer(
    overrides: [
      commitPicksProvider('/r').overrideWith((ref) => picks),
      repoActionsProvider('/r').overrideWith((ref) {
        final a = _PickActions(ref, '/r', GitWriter(_IdleGit(), '/r'));
        ref.onDispose(a.dispose);
        return actions = a;
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: PickBar(repoPath: '/r', commits: commits ?? _commits),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (container, () => actions);
}

CommitPicks _picks(List<String> shas) =>
    shas.fold(CommitPicks.none, (p, s) => p.toggle(s));

void main() {
  testWidgets('shows nothing with fewer than two picks', (tester) async {
    await _pump(tester, picks: _picks(['bbb']));
    expect(find.text('Cherry-pick'), findsNothing);
  });

  testWidgets('counts only picks still in the graph', (tester) async {
    await _pump(tester, picks: _picks(['bbb', 'gone']));
    expect(find.text('Cherry-pick'), findsNothing);
  });

  testWidgets('cherry-picks oldest first and clears the picks', (tester) async {
    final (c, actions) = await _pump(tester, picks: _picks(['ccc', 'aaa']));
    expect(find.text('2 commits selected'), findsOneWidget);

    await tester.tap(find.text('Cherry-pick'));
    await tester.pump();

    expect(actions()!.calls, ['aaa ccc']);
    expect(c.read(commitPicksProvider('/r')).isEmpty, isTrue);
  });

  testWidgets('the no-commit button picks without committing', (tester) async {
    final (_, actions) = await _pump(
      tester,
      picks: _picks(['bbb', 'ccc', 'aaa']),
    );

    await tester.tap(find.text('Cherry-pick without committing'));
    await tester.pump();

    expect(actions()!.calls, ['aaa bbb ccc --no-commit']);
  });

  testWidgets('a merge among the picks stops the batch and says why', (
    tester,
  ) async {
    final (c, actions) = await _pump(
      tester,
      picks: _picks(['ccc', 'bbb']),
      commits: [
        _commit('ccc'),
        _commit('bbb', parents: ['x', 'y']),
        _commit('aaa'),
      ],
    );

    await tester.tap(find.text('Cherry-pick'));
    await tester.pump();

    expect(actions()?.calls ?? const <String>[], isEmpty);
    final toast = c.read(toastProvider).single;
    expect(toast.kind, ToastKind.warning);
    expect(toast.description, contains('bbb'));
    // The picks stay, so the user can drop the merge and try again.
    expect(c.read(commitPicksProvider('/r')).length, 2);
    c.read(toastProvider.notifier).dismiss(toast.id);
  });

  testWidgets('Clear drops every pick', (tester) async {
    final (c, _) = await _pump(tester, picks: _picks(['ccc', 'aaa']));

    await tester.tap(find.text('Clear'));
    await tester.pump();

    expect(c.read(commitPicksProvider('/r')).isEmpty, isTrue);
    expect(find.text('Cherry-pick'), findsNothing);
  });

  for (final width in [336.0, 520.0, 800.0]) {
    testWidgets('lays out without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      await _pump(tester, picks: _picks(['ccc', 'aaa']), width: width);
      expect(tester.takeException(), isNull);
      expect(find.text('Cherry-pick without committing'), findsOneWidget);
    });
  }
}
