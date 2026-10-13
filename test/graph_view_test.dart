import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
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

Widget _harness(RepoData data, {List<SquashLink> squashLinks = const []}) =>
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GraphList(data: data, squashLinks: squashLinks),
        ),
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

  group('multi-pick clicks', () {
    Future<ProviderContainer> pumpOpen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceProvider.overrideWith(
              (ref) => WorkspaceController()..openRepo('/r'),
            ),
            bisectStateProvider('/r').overrideWith((ref) => null),
            repoDataProvider('/r').overrideWith((ref) async => _data()),
            settingsProvider.overrideWith(
              (ref) => SettingsController(
                InMemorySettingsRepository(),
                const AppSettings(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [AppTokens.dark()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: GraphList(data: _data())),
          ),
        ),
      );
      return ProviderScope.containerOf(tester.element(find.byType(GraphList)));
    }

    Future<void> clickWith(
      WidgetTester tester,
      LogicalKeyboardKey key,
      String text,
    ) async {
      await tester.sendKeyDownEvent(key);
      await tester.tap(find.text(text));
      await tester.sendKeyUpEvent(key);
      await tester.pump();
    }

    for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
      testWidgets('click then ${platform.name} toggle-click picks both and '
          'shows the bar; a plain click drops them', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final c = await pumpOpen(tester);
          final toggle = platform == TargetPlatform.macOS
              ? LogicalKeyboardKey.metaLeft
              : LogicalKeyboardKey.controlLeft;

          await tester.tap(find.text('msg bbb'));
          await tester.pump();
          await clickWith(tester, toggle, 'msg aaa');

          expect(c.read(commitPicksProvider('/r')).shas, {'bbb', 'aaa'});
          expect(c.read(selectedCommitProvider), 'aaa');
          expect(find.text('2 commits selected'), findsOneWidget);

          await tester.tap(find.text('msg fff'));
          await tester.pump();
          expect(c.read(commitPicksProvider('/r')).isEmpty, isTrue);
          expect(find.text('2 commits selected'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('right-clicking a picked row offers to pick them all; '
        'any other row does not', (tester) async {
      final c = await pumpOpen(tester);
      await c.read(repoDataProvider('/r').future);
      c.read(commitPicksProvider('/r').notifier).state = CommitPicks.none
          .toggle('bbb')
          .toggle('aaa');
      await tester.pump();

      await tester.tap(find.text('msg aaa'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Cherry-pick 2 commits'), findsOneWidget);
      expect(
        find.text('Cherry-pick 2 commits without committing'),
        findsOneWidget,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.text('msg fff'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Revert'), findsOneWidget);
      expect(find.textContaining(RegExp(r'Cherry-pick \d')), findsNothing);
    });

    testWidgets('toggling the selected row out un-highlights it', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final c = await pumpOpen(tester);
        bool lit(String sha) => tester
            .widget<CommitRow>(
              find.byWidgetPredicate(
                (w) => w is CommitRow && w.commit.sha == sha,
              ),
            )
            .selected;

        await tester.tap(find.text('msg bbb'));
        await tester.pump();
        await clickWith(tester, LogicalKeyboardKey.metaLeft, 'msg aaa');
        await clickWith(tester, LogicalKeyboardKey.metaLeft, 'msg aaa');

        expect(c.read(commitPicksProvider('/r')).shas, {'bbb'});
        expect(lit('aaa'), isFalse);
        expect(lit('bbb'), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('shift-click picks the run of rows from the selection', (
      tester,
    ) async {
      final c = await pumpOpen(tester);

      await tester.tap(find.text('msg bbb'));
      await tester.pump();
      await clickWith(tester, LogicalKeyboardKey.shiftLeft, 'msg aaa');

      expect(c.read(commitPicksProvider('/r')).shas, {'bbb', 'fff', 'aaa'});
      expect(find.text('3 commits selected'), findsOneWidget);
    });
  });

  testWidgets('keeps HEAD and tag pills inline; branch names move to the '
      'left column', (tester) async {
    await tester.pumpWidget(_harness(_data()));
    // HEAD and tags still mark their exact commit, so they stay inline.
    expect(find.text('HEAD'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
    // The local branch strand is named in the left gutter, not as a pill.
    expect(find.text('main'), findsWidgets);
    // Remote branch heads no longer render inline — the gutter carries the
    // branch identity instead.
    expect(find.text('origin/main'), findsNothing);
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
    );
    await tester.pumpWidget(
      _harness(
        data,
        squashLinks: const [SquashLink(fromSha: 'tip', toSha: 'landing')],
      ),
    );

    final overlay = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is SquashDashPainter,
    );
    expect(overlay, findsOneWidget);
  });

  testWidgets('the graph shows before squash links are inferred, and the '
      'overlay joins it when they are', (tester) async {
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
    );
    final links = Completer<List<SquashLink>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(
            (ref) => WorkspaceController()..openRepo('/r'),
          ),
          bisectStateProvider('/r').overrideWith((ref) => null),
          repoDataProvider('/r').overrideWith((ref) async => data),
          squashLinksProvider('/r').overrideWith((ref) => links.future),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: GraphView()),
        ),
      ),
    );
    await tester.pump();

    final overlay = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is SquashDashPainter,
    );
    expect(find.text('msg landing'), findsOneWidget);
    expect(overlay, findsNothing);

    links.complete(const [SquashLink(fromSha: 'tip', toSha: 'landing')]);
    await tester.pump();
    expect(overlay, findsOneWidget);
  });

  testWidgets('shared ancestors are labelled by the base branch, not a '
      'newer branch containing them', (tester) async {
    // c1(ref feat/stage-3) → c2(ref main) → c3(no ref). All on lane 0. Shas are
    // kept distinct from the branch names so the SHA column can't be mistaken
    // for a gutter label.
    final data = RepoData(
      commits: assignLanes([
        _c(
          'c1',
          ['c2'],
          refs: const [GitRef(kind: RefKind.local, name: 'feat/stage-3')],
        ),
        _c(
          'c2',
          ['c3'],
          refs: const [GitRef(kind: RefKind.local, name: 'main')],
        ),
        _c('c3', const []),
      ]),
      branches: const [
        Branch(name: 'feat/stage-3', current: true),
        Branch(name: 'main'),
      ],
    );
    await tester.pumpWidget(_harness(data));

    // feat/stage-3 names only its own tip; it must not leak down onto the
    // shared history. main names its own segment (the ancestor inherits it
    // silently, so the gutter prints it once). Both appear exactly once.
    expect(find.text('feat/stage-3'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);

    // The feat/stage-3 label sits on its own tip row, never on the base commit.
    final mainRow = find.ancestor(
      of: find.text('msg c2'),
      matching: find.byType(CommitRow),
    );
    expect(
      find.descendant(of: mainRow, matching: find.text('feat/stage-3')),
      findsNothing,
    );
  });
}
