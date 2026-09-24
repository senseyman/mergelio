import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/ui/graph/bisect_bar.dart';

BisectState _state({
  required List<BisectMark> marks,
  int left = -1,
  int steps = -1,
  String? firstBad,
}) => BisectState(
  marks: marks,
  terms: const BisectTerms(),
  currentSha: 'head1111',
  revisionsLeft: left,
  steps: steps,
  firstBad: firstBad,
);

Commit _commit(
  String sha, {
  String message = 'subject',
  String author = 'Ada Lovelace',
  List<String> parents = const [],
}) => Commit(
  sha: sha,
  message: message,
  author: author,
  authorEmail: 'ada@example.com',
  date: DateTime(2026, 5, 1),
  parents: parents,
);

/// The finished state the hunt ends in, with [firstBad] as the answer.
BisectState _finishedOn(String firstBad) => _state(
  marks: [BisectMark(firstBad, BisectKind.bad)],
  left: 0,
  firstBad: firstBad,
);

/// Never runs: the bar's log tests script the answer at the actions layer,
/// so the writer underneath it only has to exist.
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

/// Actions whose bisect log is decided by the test rather than by a
/// repository: [log] is the trail to hand back, or null for a fetch that
/// failed and was already reported.
class _LogActions extends RepoActions {
  final String? log;
  int fetches = 0;

  _LogActions(super.ref, super.path, super.writer, {required this.log});

  @override
  Future<String?> bisectLog() async {
    fetches++;
    return log;
  }
}

Future<void> _pump(
  WidgetTester tester,
  BisectState? state, {
  void Function(String sha)? onJumpToCommit,
  List<Commit> commits = const [],
  ({String? text})? log,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bisectStateProvider('/r').overrideWith((ref) async => state),
        // Resolved synchronously: the bar reads the loaded page to put a
        // subject and an author against the sha, and a provider that reaches
        // the filesystem would never resolve under a widget test.
        repoDataProvider('/r')
            .overrideWith((ref) => RepoData(commits: commits)),
        // Only the tests that open the log panel script it; the rest keep the
        // real actions object the rest of the bar is wired to.
        if (log != null)
          repoActionsProvider('/r').overrideWith(
            (ref) => _LogActions(
              ref,
              '/r',
              GitWriter(_IdleGit(), '/r'),
              log: log.text,
            ),
          ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BisectBar(
            repoPath: '/r',
            onJumpToCommit: onJumpToCommit ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The bisect state a test can move under a bar that stays mounted, so a hunt
/// can be driven from running to finished the way a real one arrives rather
/// than by remounting the widget on an already-finished state.
final _driver = StateProvider<BisectState?>((_) => null);

Future<ProviderContainer> _pumpLive(
  WidgetTester tester, {
  required BisectState? initial,
  List<Commit> commits = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      bisectStateProvider('/r').overrideWith((ref) => ref.watch(_driver)),
      repoDataProvider('/r').overrideWith((ref) => RepoData(commits: commits)),
    ],
  );
  addTearDown(container.dispose);
  container.read(_driver.notifier).state = initial;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BisectBar(repoPath: '/r', onJumpToCommit: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// A hunt still narrowing: a bad and a good end, candidates left.
BisectState _running() => _state(
  marks: const [
    BisectMark('aaa1111', BisectKind.bad),
    BisectMark('ccc3333', BisectKind.good),
  ],
  left: 3,
  steps: 2,
);

void main() {
  testWidgets('no active bisect renders nothing', (tester) async {
    await _pump(tester, null);
    expect(find.byType(BisectBar), findsOneWidget);
    expect(find.text('Good'), findsNothing);
  });

  testWidgets(
    'no marks yet shows the bare-start message and reset, no counts',
    (tester) async {
      await _pump(tester, _state(marks: const []));
      expect(
        find.text('Bisecting. Mark a bad commit to begin.'),
        findsOneWidget,
      );
      expect(find.text('Reset bisect'), findsOneWidget);
      expect(find.text('Good'), findsNothing);
      expect(find.text('Bad'), findsNothing);
      // The defensive guard: a -1 sentinel must never reach the screen.
      expect(find.textContaining('-1'), findsNothing);
    },
  );

  testWidgets(
    'a good-only mark (no bad yet) still shows the bare-start message, '
    'not testing/verdict UI',
    (tester) async {
      await _pump(
        tester,
        _state(marks: const [BisectMark('bbb2222', BisectKind.good)]),
      );
      expect(
        find.text('Bisecting. Mark a bad commit to begin.'),
        findsOneWidget,
      );
      expect(find.textContaining('Testing'), findsNothing);
      expect(find.text('Good'), findsNothing);
      expect(find.text('Bad'), findsNothing);
      expect(find.text('Skip'), findsNothing);
    },
  );

  testWidgets('awaiting good shows guidance and reset only', (tester) async {
    await _pump(
      tester,
      _state(marks: const [BisectMark('aaa1111', BisectKind.bad)]),
    );
    expect(
      find.text('Bisecting. Mark a commit you know is good.'),
      findsOneWidget,
    );
    expect(find.text('Reset bisect'), findsOneWidget);
    expect(find.text('Good'), findsNothing);
    expect(find.text('Bad'), findsNothing);
    expect(find.textContaining('-1'), findsNothing);
  });

  testWidgets('running shows counts, testing sha and verdict buttons', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        marks: const [
          BisectMark('aaa1111', BisectKind.bad),
          BisectMark('bbb2222', BisectKind.good),
        ],
        left: 12,
        steps: 4,
      ),
    );
    expect(find.text('12 revisions left'), findsOneWidget);
    expect(find.text('about 4 steps'), findsOneWidget);
    expect(find.text('Testing head111'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Bad'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Reset bisect'), findsOneWidget);
  });

  testWidgets('one revision left reads in singular', (tester) async {
    await _pump(
      tester,
      _state(
        marks: const [
          BisectMark('aaa1111', BisectKind.bad),
          BisectMark('bbb2222', BisectKind.good),
        ],
        left: 1,
        steps: 1,
      ),
    );
    expect(find.text('1 revision left'), findsOneWidget);
    expect(find.text('about 1 step'), findsOneWidget);
  });

  testWidgets(
    'running never renders a negative count even if vars are unresolved',
    (tester) async {
      await _pump(
        tester,
        _state(
          marks: const [
            BisectMark('aaa1111', BisectKind.bad),
            BisectMark('bbb2222', BisectKind.good),
          ],
        ),
      );
      expect(find.textContaining('-1'), findsNothing);
      expect(find.text('Testing head111'), findsOneWidget);
    },
  );

  testWidgets('finished shows first bad card, not verdicts', (tester) async {
    await _pump(
      tester,
      _state(
        marks: const [BisectMark('aaa1111', BisectKind.bad)],
        left: 0,
        firstBad: 'aaa1111',
      ),
    );
    expect(find.text('First bad commit'), findsOneWidget);
    expect(find.text('Jump to commit'), findsOneWidget);
    expect(find.text('Copy SHA'), findsOneWidget);
    expect(find.text('Good'), findsNothing);
    expect(find.text('Bad'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('jump to commit reports the first bad sha', (tester) async {
    String? jumped;
    await _pump(
      tester,
      _state(
        marks: const [BisectMark('aaa1111', BisectKind.bad)],
        left: 0,
        firstBad: 'aaa1111',
      ),
      onJumpToCommit: (sha) => jumped = sha,
    );
    await tester.tap(find.text('Jump to commit'));
    await tester.pumpAndSettle();
    expect(jumped, 'aaa1111');
  });

  testWidgets('finished card names the commit, not just its sha', (
    tester,
  ) async {
    await _pump(
      tester,
      _finishedOn('aaa1111'),
      commits: [
        _commit('aaa1111', message: 'Break the parser', author: 'Ada Lovelace'),
      ],
    );
    expect(find.text('First bad commit'), findsOneWidget);
    expect(find.text('Break the parser'), findsOneWidget);
    expect(find.textContaining('Ada Lovelace'), findsOneWidget);
    expect(find.textContaining('aaa1111'), findsOneWidget);
  });

  testWidgets(
    'a first bad commit outside the loaded page still shows its sha',
    (tester) async {
      await _pump(
        tester,
        _finishedOn('aaa1111'),
        commits: [_commit('bbb2222', message: 'Some other commit')],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('First bad commit'), findsOneWidget);
      expect(find.textContaining('aaa1111'), findsOneWidget);
      // The subject of an unrelated commit must never stand in for the
      // answer: better a bare sha than the wrong commit named.
      expect(find.text('Some other commit'), findsNothing);
      expect(find.text('Jump to commit'), findsOneWidget);
      expect(find.text('Copy SHA'), findsOneWidget);
    },
  );

  testWidgets('finished card wraps without overflow at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      _finishedOn('aaa1111'),
      commits: [
        _commit(
          'aaa1111',
          message:
              'Rewrite the whole lane layout pass so that long subjects like '
              'this one cannot push the bisect bar off the side of a narrow '
              'window',
          author: 'Grace Brewster Murray Hopper',
        ),
      ],
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a loaded plain commit can be reverted straight from the card', (
    tester,
  ) async {
    await _pump(
      tester,
      _finishedOn('aaa1111'),
      commits: [_commit('aaa1111', message: 'Break the parser')],
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Revert this commit'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('reverting a merge asks which parent to keep first', (
    tester,
  ) async {
    await _pump(
      tester,
      _finishedOn('aaa1111'),
      commits: [
        _commit(
          'aaa1111',
          message: 'Merge topic into main',
          parents: const ['ccc3333', 'ddd4444'],
        ),
        _commit('ccc3333', message: 'Mainline side'),
        _commit('ddd4444', message: 'Topic side'),
      ],
    );

    await tester.tap(find.text('Revert this commit'));
    await tester.pumpAndSettle();

    // The graph's own picker, reached with the revert wording and this
    // commit: git refuses a merge revert without being told the mainline,
    // and the bar must not hand it one it never asked for.
    expect(find.text('Revert merge aaa1111'), findsOneWidget);
    expect(find.text('Mainline side'), findsOneWidget);
    expect(find.text('Topic side'), findsOneWidget);
  });

  testWidgets(
    'revert is disabled, with a reason, when the commit is not loaded',
    (tester) async {
      await _pump(
        tester,
        _finishedOn('aaa1111'),
        commits: [_commit('bbb2222', message: 'Some other commit')],
      );
      // Nothing here knows whether the culprit is a merge, so there is no
      // honest revert to offer — better to say so than to let git error.
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Revert this commit'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.byTooltip(
          'This commit is outside the loaded history. Scroll the graph to '
          'load it, then revert it from its row.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('the hunt landing puts the graph cursor on the culprit', (
    tester,
  ) async {
    final c = await _pumpLive(
      tester,
      initial: _running(),
      commits: [_commit('aaa1111', message: 'Break the parser')],
    );
    expect(
      c.read(selectedCommitProvider),
      isNull,
      reason: 'a running hunt selects nothing',
    );

    c.read(_driver.notifier).state = _finishedOn('aaa1111');
    await tester.pumpAndSettle();

    expect(c.read(selectedCommitProvider), 'aaa1111');
  });

  testWidgets('a rebuild after the user picks another row leaves it alone', (
    tester,
  ) async {
    final c = await _pumpLive(
      tester,
      initial: _running(),
      commits: [_commit('aaa1111'), _commit('bbb2222')],
    );
    c.read(_driver.notifier).state = _finishedOn('aaa1111');
    await tester.pumpAndSettle();
    expect(c.read(selectedCommitProvider), 'aaa1111');

    // The user reads the culprit, then clicks a different row to look around.
    c.read(selectedCommitProvider.notifier).state = 'bbb2222';
    // A refresh re-reads the same finished bisect: a fresh object carrying
    // the same answer. Re-asserting the cursor here would yank it back every
    // time anything in the repository changed.
    c.read(_driver.notifier).state = _finishedOn('aaa1111');
    await tester.pumpAndSettle();

    expect(c.read(selectedCommitProvider), 'bbb2222');
  });

  testWidgets('running row wraps without overflow at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      _state(
        marks: const [
          BisectMark('aaa1111', BisectKind.bad),
          BisectMark('bbb2222', BisectKind.good),
        ],
        left: 12,
        steps: 4,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  /// Watches what the card actually hands the platform, so the assertion is on
  /// the text that reaches the clipboard rather than on the widget that asked.
  String? clipboardText;

  void watchClipboard() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  testWidgets('the finished card copies a fixup line for the culprit', (
    tester,
  ) async {
    watchClipboard();
    await _pump(
      tester,
      _finishedOn('aaa1111'),
      commits: [_commit('aaa1111', message: 'Break parser')],
    );

    await tester.tap(find.text('Copy fixup!'));
    await tester.pumpAndSettle();

    // Exactly what `git commit --fixup` writes: the marker, one space, the
    // subject, and nothing else for git to fail to match on.
    expect(clipboardText, 'fixup! Break parser');
  });

  testWidgets('only the subject line reaches the fixup, never the body', (
    tester,
  ) async {
    watchClipboard();
    await _pump(
      tester,
      _finishedOn('aaa1111'),
      commits: [
        _commit(
          'aaa1111',
          message: 'Break parser\n\nThe body explains why at length.\n',
        ),
      ],
    );

    await tester.tap(find.text('Copy fixup!'));
    await tester.pumpAndSettle();

    expect(clipboardText, 'fixup! Break parser');
  });

  testWidgets('no fixup action when the culprit is outside the loaded page', (
    tester,
  ) async {
    await _pump(
      tester,
      _finishedOn('aaa1111'),
      commits: [_commit('bbb2222', message: 'Some other commit')],
    );

    // Without the commit there is no subject to name, and a fixup line git
    // cannot match onto anything is worse than no action at all.
    expect(find.text('Copy fixup!'), findsNothing);
    expect(find.text('Copy SHA'), findsOneWidget);
  });

  const trail =
      'git bisect start\n'
      'git bisect bad aaa1111\n'
      'git bisect good ccc3333\n';

  testWidgets('the log toggle is offered while the hunt is still narrowing', (
    tester,
  ) async {
    await _pump(tester, _running(), log: (text: trail));
    expect(find.text('Log'), findsOneWidget);
    // Closed until asked for: the trail is reference material, not something
    // to spend the commit list's height on unprompted.
    expect(find.textContaining('git bisect bad aaa1111'), findsNothing);
  });

  testWidgets('the log toggle is offered on the finished card too', (
    tester,
  ) async {
    await _pump(
      tester,
      _finishedOn('aaa1111'),
      commits: [_commit('aaa1111')],
      log: (text: trail),
    );
    expect(find.text('Log'), findsOneWidget);
  });

  testWidgets('expanding the log shows the trail git recorded', (tester) async {
    await _pump(tester, _running(), log: (text: trail));

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    expect(find.textContaining('git bisect good ccc3333'), findsOneWidget);
  });

  testWidgets('toggling the log again puts it away', (tester) async {
    await _pump(tester, _running(), log: (text: trail));

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('git bisect start'), findsOneWidget);

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    expect(find.textContaining('git bisect start'), findsNothing);
  });

  testWidgets('a failed fetch says so rather than opening an empty panel', (
    tester,
  ) async {
    // The actions layer has already toasted git's own words; what is left for
    // the panel is to not sit there blank as if the hunt recorded nothing.
    await _pump(tester, _running(), log: (text: null));

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    expect(find.text('The bisect log could not be read.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a log git printed nothing for says so as well', (tester) async {
    await _pump(tester, _running(), log: (text: '\n  \n'));

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    expect(find.text('No verdicts recorded yet.'), findsOneWidget);
  });

  testWidgets('a long log scrolls inside the bar instead of growing it', (
    tester,
  ) async {
    final long = [
      for (var i = 0; i < 200; i++) 'git bisect good ${i.toString() * 7}',
    ].join('\n');
    await _pump(tester, _running(), log: (text: long));
    final closed = tester.getSize(find.byType(BisectBar)).height;

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    // The bar takes its height out of the commit list below it, so a trail
    // 200 verdicts long must not be allowed to push the graph off screen.
    final open = tester.getSize(find.byType(BisectBar)).height;
    expect(open, greaterThan(closed));
    expect(open, lessThan(400));
    expect(
      find.descendant(
        of: find.byType(BisectBar),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bar with its log open lays out at a narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      _running(),
      log: (
        text:
            'git bisect start\n'
            'git bisect bad 0123456789abcdef0123456789abcdef01234567\n',
      ),
    );

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
