import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/graph/commit_row.dart';
import 'package:mergelio/ui/graph/graph_view.dart';
import 'package:mergelio/ui/graph/squash_overlay.dart';

Commit _c(String sha, List<String> parents, {List<GitRef> refs = const []}) =>
    Commit(
      sha: sha,
      message: 'msg $sha',
      author: 'Tester',
      authorEmail: 't@e',
      date: DateTime(2026, 7, 1),
      parents: parents,
      refs: refs,
      signed: sha == 'bbb',
    );

/// A merge topology so the rail paints every connector kind, with refs of all
/// kinds so pills render.
RepoData _data({List<WorkingFile> working = const []}) => RepoData(
  commits: assignLanes([
    _c(
      'bbb',
      ['aaa', 'fff'],
      refs: const [
        GitRef(kind: RefKind.head, name: 'HEAD'),
        GitRef(kind: RefKind.local, name: 'main'),
        GitRef(kind: RefKind.remote, name: 'origin/main'),
      ],
    ),
    _c(
      'fff',
      ['aaa'],
      refs: const [GitRef(kind: RefKind.tag, name: 'v1')],
    ),
    _c('aaa', []),
  ]),
  branches: const [Branch(name: 'main', current: true)],
  working: working,
);

Widget _harness(RepoData data) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
  ],
  child: MaterialApp(
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(body: GraphList(data: data)),
  ),
);

void main() {
  testWidgets('renders a row per commit with message and short sha', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_data()));
    expect(find.text('msg bbb'), findsOneWidget);
    expect(find.text('msg aaa'), findsOneWidget);
    expect(find.text('bbb'), findsOneWidget);
  });

  testWidgets('shows a WIP row only when the working tree is dirty', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_data()));
    expect(find.text('WIP'), findsNothing);

    await tester.pumpWidget(
      _harness(
        _data(
          working: const [
            WorkingFile(path: 'a.txt', worktree: GitChange.modified),
            WorkingFile(path: 'b.txt', worktree: GitChange.added),
          ],
        ),
      ),
    );
    expect(find.text('WIP'), findsOneWidget);
    expect(find.text('Uncommitted changes · 2 files'), findsOneWidget);
  });

  testWidgets('tap selects; arrow keys move the selection', (tester) async {
    await tester.pumpWidget(_harness(_data()));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GraphList)),
    );

    await tester.tap(find.text('msg bbb'));
    await tester.pump();
    expect(container.read(selectedCommitProvider), 'bbb');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(container.read(selectedCommitProvider), 'fff');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(container.read(selectedCommitProvider), 'aaa');

    // Already at the bottom: stays put.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(container.read(selectedCommitProvider), 'aaa');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(container.read(selectedCommitProvider), 'fff');
  });

  testWidgets('renders ref pills for head, local, remote and tag refs', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_data()));
    expect(find.text('HEAD'), findsOneWidget);
    expect(find.text('main'), findsWidgets);
    expect(find.text('origin/main'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
  });

  testWidgets('paints a squash overlay when links are present', (tester) async {
    final data = RepoData(
      commits: assignLanes([
        _c(
          'landing',
          ['base'],
          refs: const [GitRef(kind: RefKind.local, name: 'main')],
        ),
        _c('base', const []),
        _c(
          'tip',
          ['base'],
          refs: const [GitRef(kind: RefKind.local, name: 'feature')],
        ),
      ]),
      branches: const [Branch(name: 'main', current: true)],
      squashLinks: const [SquashLink(fromSha: 'tip', toSha: 'landing')],
    );
    await tester.pumpWidget(_harness(data));

    final overlay = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is SquashOverlayPainter,
    );
    expect(overlay, findsOneWidget);
  });

  testWidgets('shared ancestors are labelled by the base branch, not a '
      'newer branch containing them', (tester) async {
    // stage3(ref feat/stage-3) → main(ref main) → root(no ref). All on lane 0.
    final data = RepoData(
      commits: assignLanes([
        _c(
          'stage3',
          ['main'],
          refs: const [GitRef(kind: RefKind.local, name: 'feat/stage-3')],
        ),
        _c(
          'main',
          ['root'],
          refs: const [GitRef(kind: RefKind.local, name: 'main')],
        ),
        _c('root', const []),
      ]),
      branches: const [
        Branch(name: 'feat/stage-3', current: true),
        Branch(name: 'main'),
      ],
    );
    await tester.pumpWidget(_harness(data));

    // The root commit's meta line names main (its nearest ref-bearing
    // first-parent descendant), never feat/stage-3.
    final rootRow = find.ancestor(
      of: find.text('msg root'),
      matching: find.byType(CommitRow),
    );
    expect(
      find.descendant(of: rootRow, matching: find.text('main')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rootRow, matching: find.text('feat/stage-3')),
      findsNothing,
    );
  });
}
