import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/review.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/file_insight.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/review.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/review/review_view.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

class _FakeForge implements Forge {
  final List<PullRequest> prs;
  final bool fail;
  final asked = <String>[];
  _FakeForge(this.prs, {this.fail = false});

  @override
  ForgeHost get host => _host;

  @override
  Future<List<PullRequest>> pullRequestsForBranch(
    String branch, {
    int limit = 50,
  }) async {
    asked.add(branch);
    if (fail) throw const ForgeOffline('down');
    return prs;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PullRequest _pr(int n, String target) => PullRequest(
  number: n,
  title: 't',
  state: PullRequestState.open,
  author: const ForgeUser(login: 'u'),
  sourceBranch: 'feature',
  targetBranch: target,
  headSha: 'h',
);

const _target = ReviewTarget(repoPath: '/repo', base: 'main', head: 'feature');

const _files = [
  ReviewFile(
    change: CommitFileChange(path: 'lib/a.dart', change: GitChange.modified),
    fingerprint: 'fp-a',
    adds: 1,
    dels: 1,
  ),
  ReviewFile(
    change: CommitFileChange(path: 'lib/b.dart', change: GitChange.added),
    fingerprint: 'fp-b',
    adds: 1,
  ),
];

ReviewSummary _summary({
  bool related = true,
  int ahead = 2,
  List<ReviewFile> files = _files,
}) {
  final mergeBase = related ? 'm' * 40 : null;
  return ReviewSummary(
    baseSha: 'b' * 40,
    headSha: 'h' * 40,
    mergeBase: mergeBase,
    fromRev: mergeBase,
    counts: (behind: 1, ahead: ahead),
    commits: [
      Commit(
        sha: 'c' * 40,
        message: 'Add the widget',
        author: 'Ana',
        authorEmail: 'a@e.com',
        date: DateTime(2026, 10, 1),
      ),
    ],
    commitsTruncated: false,
    files: mergeBase == null ? const [] : files,
  );
}

final _diffs = <String, FileDiff?>{
  'lib/a.dart': const FileDiff(
    path: 'lib/a.dart',
    status: GitChange.modified,
    hunks: [
      DiffHunk(
        header: '@@ -1,2 +1,2 @@',
        oldStart: 1,
        newStart: 1,
        lines: [
          DiffLine(type: DiffLineType.del, oldNo: 1, text: 'old line'),
          DiffLine(type: DiffLineType.add, newNo: 1, text: 'new line'),
        ],
      ),
    ],
  ),
  'lib/b.dart': const FileDiff(
    path: 'lib/b.dart',
    status: GitChange.added,
    hunks: [
      DiffHunk(
        header: '@@ -0,0 +1 @@',
        oldStart: 0,
        newStart: 1,
        lines: [DiffLine(type: DiffLineType.add, newNo: 1, text: 'fresh')],
      ),
    ],
  ),
};

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  ReviewSummary? summary,
  Map<String, FileDiff?>? diffs,
  List<String>? diffsRead,
  ReviewPrQuery? prQuery,
  Forge? forge,
  List<Uri>? launched,
  List<LineRangeKey>? lineHistoryAsked,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      reviewSummaryProvider.overrideWith((ref, t) async {
        final s = summary ?? _summary();
        // Tip to tip reads from base's own tip.
        return t.threeDot
            ? s
            : ReviewSummary(
                baseSha: s.baseSha,
                headSha: s.headSha,
                mergeBase: s.mergeBase,
                fromRev: s.baseSha,
                counts: s.counts,
                commits: s.commits,
                commitsTruncated: false,
                files: _summary().files,
              );
      }),
      reviewFileDiffProvider.overrideWith((ref, k) async {
        diffsRead?.add(k.path);
        final all = diffs ?? _diffs;
        if (!all.containsKey(k.path)) throw StateError('no diff');
        return all[k.path];
      }),
      reviewPrQueryProvider.overrideWith((ref, t) async => prQuery),
      forgeProvider.overrideWith((ref, p) async => forge),
      forgeLaunchUrlProvider.overrideWithValue((uri) async {
        launched?.add(uri);
        return true;
      }),
      lineHistoryProvider.overrideWith((ref, key) async {
        lineHistoryAsked?.add(key);
        return const [];
      }),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(reviewTargetProvider.notifier).state = _target;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ReviewView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('states the three-dot range and how far apart the sides are', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('main...feature'), findsOneWidget);
    expect(find.text('feature is 2 ahead, 1 behind main'), findsOneWidget);
    expect(find.text('Add the widget'), findsOneWidget);
    expect(find.text('new line'), findsOneWidget);
    expect(find.text('fresh'), findsOneWidget);
    expect(find.text('0 of 2 viewed'), findsOneWidget);
  });

  testWidgets('switching to tip to tip says so', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Tip to tip'));
    await tester.pumpAndSettle();
    expect(c.read(reviewTargetProvider)!.threeDot, isFalse);
    expect(find.textContaining('main..feature'), findsOneWidget);
    expect(find.textContaining('main...feature'), findsNothing);
  });

  testWidgets('ticking viewed puts the file away and counts it', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('rv-viewed-lib/a.dart')));
    await tester.pumpAndSettle();
    expect(find.text('new line'), findsNothing);
    expect(find.text('fresh'), findsOneWidget);
    expect(find.text('1 of 2 viewed'), findsOneWidget);

    // The chevron still opens a viewed file on request.
    await tester.tap(find.byKey(const ValueKey('rv-toggle-lib/a.dart')));
    await tester.pumpAndSettle();
    expect(find.text('new line'), findsOneWidget);
  });

  testWidgets('collapse all hides every diff', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.text('new line'), findsNothing);
    expect(find.text('fresh'), findsNothing);
  });

  testWidgets('no merge base is said out loud, with a way forward', (
    tester,
  ) async {
    final c = await _pump(tester, summary: _summary(related: false));
    expect(find.textContaining('share no history'), findsOneWidget);
    // Head's commits need no merge base, so they still show.
    expect(find.text('Add the widget'), findsOneWidget);
    await tester.tap(find.text('Show tip to tip'));
    await tester.pumpAndSettle();
    expect(c.read(reviewTargetProvider)!.threeDot, isFalse);
  });

  testWidgets('without a branch on a forge there is no PR button', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Open pull request'), findsNothing);
  });

  testWidgets('the PR is looked up only when the button is pressed', (
    tester,
  ) async {
    final launched = <Uri>[];
    final forge = _FakeForge([_pr(42, 'main')]);
    await _pump(
      tester,
      launched: launched,
      forge: forge,
      prQuery: (host: _host, head: 'feature', base: 'main'),
    );
    expect(forge.asked, isEmpty);

    await tester.tap(find.text('Open pull request'));
    await tester.pumpAndSettle();
    expect(forge.asked, ['feature']);
    expect(launched.single.toString(), 'https://github.com/o/r/pull/42');
  });

  testWidgets('no matching request says so instead of opening anything', (
    tester,
  ) async {
    final launched = <Uri>[];
    final c = await _pump(
      tester,
      launched: launched,
      forge: _FakeForge(const []),
      prQuery: (host: _host, head: 'feature', base: 'main'),
    );
    await tester.tap(find.text('Open pull request'));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    expect(
      c.read(toastProvider).single.title,
      'No single open pull request for feature',
    );
    // Let the toast's own dismiss timer run out.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a forge failure is reported, not swallowed', (tester) async {
    final c = await _pump(
      tester,
      forge: _FakeForge(const [], fail: true),
      prQuery: (host: _host, head: 'feature', base: 'main'),
    );
    await tester.tap(find.text('Open pull request'));
    await tester.pumpAndSettle();
    final toast = c.read(toastProvider).single;
    expect(toast.title, 'Could not look up the pull request');
    expect(toast.kind, ToastKind.error);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a file whose diff will not read can still be ticked', (
    tester,
  ) async {
    final c = await _pump(tester, diffs: {'lib/b.dart': _diffs['lib/b.dart']});
    expect(find.text("Could not read this file's diff"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rv-viewed-lib/a.dart')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 viewed'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rv-toggle-lib/a.dart')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in diff viewer'));
    await tester.pumpAndSettle();
    expect(c.read(diffTargetProvider)?.path, 'lib/a.dart');
  });

  testWidgets('git printing no diff for a listed file says so too', (
    tester,
  ) async {
    await _pump(tester, diffs: {'lib/a.dart': null, 'lib/b.dart': null});
    expect(find.text("Could not read this file's diff"), findsNWidgets(2));
  });

  testWidgets('a collapsed file is never read', (tester) async {
    final read = <String>[];
    await _pump(
      tester,
      diffsRead: read,
      summary: _summary(
        files: [
          _files[0],
          const ReviewFile(
            change: CommitFileChange(path: 'big.txt', change: GitChange.added),
            fingerprint: 'fp-big',
            adds: kReviewLargeDiffLines + 1,
          ),
        ],
      ),
    );
    expect(read, ['lib/a.dart']);
    expect(find.textContaining('Large diff'), findsOneWidget);
  });

  testWidgets('a file far down the review is read only once scrolled to', (
    tester,
  ) async {
    final read = <String>[];
    final many = [
      for (var i = 0; i < 60; i++)
        ReviewFile(
          change: CommitFileChange(path: 'f$i.txt', change: GitChange.added),
          fingerprint: 'fp$i',
          adds: 1,
        ),
    ];
    await _pump(
      tester,
      diffsRead: read,
      summary: _summary(files: many),
      diffs: {
        for (final f in many)
          f.change.path: FileDiff(
            path: f.change.path,
            status: GitChange.added,
            hunks: [
              DiffHunk(
                header: '@@ -0,0 +1 @@',
                oldStart: 0,
                newStart: 1,
                lines: [DiffLine(type: DiffLineType.add, newNo: 1, text: 'x')],
              ),
            ],
          ),
      },
    );
    expect(read, contains('f0.txt'));
    expect(read, isNot(contains('f59.txt')));
    expect(read.length, lessThan(many.length));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(read, contains('f59.txt'));
  });

  testWidgets('a removed line\'s history is read on the base side', (
    tester,
  ) async {
    final asked = <LineRangeKey>[];
    await _pump(tester, lineHistoryAsked: asked);
    final at = tester.getCenter(find.text('old line'));
    await tester.tapAt(at, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Line history'));
    await tester.pumpAndSettle();
    expect(asked.single.rev, 'm' * 40);
    expect((asked.single.start, asked.single.end), (1, 1));
  });

  testWidgets('tapping a commit selects it', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Add the widget'));
    await tester.pumpAndSettle();
    expect(c.read(selectedCommitProvider), 'c' * 40);
  });

  testWidgets('fits the smallest centre column without overflow', (
    tester,
  ) async {
    await _pump(tester);
    for (final w in [336.0, 480.0, 640.0, 900.0]) {
      tester.view.physicalSize = Size(w, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $w');
    }
  });

  bool exportEnabled(WidgetTester tester) => tester
      .widget<PopupMenuButton<void>>(
        find.widgetWithText(PopupMenuButton<void>, 'Export patches'),
      )
      .enabled;

  testWidgets('export is offered when head has commits of its own', (
    tester,
  ) async {
    await _pump(tester);
    expect(exportEnabled(tester), isTrue);
  });

  testWidgets('export waits for head to have commits of its own', (
    tester,
  ) async {
    await _pump(tester, summary: _summary(ahead: 0));
    expect(exportEnabled(tester), isFalse);
  });
}
