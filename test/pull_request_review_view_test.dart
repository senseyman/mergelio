import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/review.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge.dart';
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

final _head = 'a' * 40;
final _base = 'b' * 40;

ReviewTarget _target({ReviewPullRequest? pr = _pr}) =>
    ReviewTarget(repoPath: '/repo', base: _base, head: _head, pullRequest: pr);

const _pr = ReviewPullRequest(
  kind: ForgeKind.github,
  number: 7,
  targetBranch: 'main',
);

PullRequestDetail _detail({String body = '## Why\n\nBecause it helps.'}) =>
    PullRequestDetail(
      request: PullRequest(
        number: 7,
        title: 'Add the thing',
        state: PullRequestState.open,
        author: const ForgeUser(login: 'ann'),
        sourceBranch: 'feature/x',
        targetBranch: 'main',
        headSha: _head,
      ),
      body: body,
    );

final _summary = ReviewSummary(
  baseSha: _base,
  headSha: _head,
  mergeBase: 'm' * 40,
  fromRev: 'm' * 40,
  counts: (behind: 0, ahead: 1),
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
  files: const [
    ReviewFile(
      change: CommitFileChange(path: 'lib/a.dart', change: GitChange.added),
      fingerprint: 'fp',
      adds: 1,
    ),
  ],
);

class _Seen {
  final details = <PullRequestKey>[];
  final checks = <ReviewChecksKey>[];
  final launched = <Uri>[];
}

Future<_Seen> _pump(
  WidgetTester tester, {
  ReviewTarget? target,
  Future<PullRequestDetail?> Function()? detail,
  Future<ChecksSummary?> Function()? checks,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final seen = _Seen();
  final container = ProviderContainer(
    overrides: [
      reviewSummaryProvider.overrideWith((ref, t) async => _summary),
      reviewFileDiffProvider.overrideWith((ref, k) async => null),
      reviewPrQueryProvider.overrideWith((ref, t) async => null),
      forgeHostProvider.overrideWith((ref, p) async => _host),
      forgeProvider.overrideWith((ref, p) async => null),
      pullRequestDetailProvider.overrideWith((ref, k) async {
        seen.details.add(k);
        return (detail ?? () async => _detail())();
      }),
      pullRequestChecksProvider.overrideWith((ref, k) async {
        seen.checks.add(k);
        return (checks ??
            () async => ChecksSummary.from(const [
              CheckRun(name: 'build', state: CheckState.success),
              CheckRun(
                name: 'lint',
                state: CheckState.failure,
                detailsHint: '3 problems',
              ),
            ]))();
      }),
      forgeLaunchUrlProvider.overrideWithValue((uri) async {
        seen.launched.add(uri);
        return true;
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
  container.read(reviewTargetProvider.notifier).state = target ?? _target();
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
  return seen;
}

void main() {
  testWidgets('names the sides after the request', (tester) async {
    await _pump(tester);
    expect(find.text('main'), findsWidgets);
    // The header pill and the request's own heading.
    expect(find.text('#7'), findsNWidgets(2));
    expect(find.textContaining('main...#7'), findsOneWidget);
  });

  testWidgets('shows the title, author and description rendered', (
    tester,
  ) async {
    final seen = await _pump(tester);

    expect(find.text('Add the thing'), findsOneWidget);
    expect(find.textContaining('ann'), findsWidgets);
    // Rendered, not source: the heading marker is gone.
    expect(find.text('Why'), findsOneWidget);
    expect(find.textContaining('## Why'), findsNothing);
    expect(find.text('Because it helps.'), findsOneWidget);
    expect(seen.details, [(repoPath: '/repo', number: 7)]);
    // The diff below is still there.
    expect(find.text('Add the widget'), findsOneWidget);
  });

  testWidgets('lists every CI job for the reviewed commit', (tester) async {
    final seen = await _pump(tester);

    expect(seen.checks, [(repoPath: '/repo', sha: _head)]);
    expect(find.text('build'), findsOneWidget);
    expect(find.text('lint'), findsOneWidget);
    expect(find.text('3 problems'), findsOneWidget);
  });

  testWidgets('a commit with no CI says so', (tester) async {
    await _pump(
      tester,
      checks: () async => const ChecksSummary(overall: ChecksOverall.none),
    );
    expect(find.text('No checks reported for this commit'), findsOneWidget);
  });

  testWidgets('an empty description says so rather than showing nothing', (
    tester,
  ) async {
    await _pump(tester, detail: () async => _detail(body: '  \n'));
    expect(find.text('No description provided.'), findsOneWidget);
  });

  testWidgets('a forge failure costs the header, not the diff', (tester) async {
    await _pump(tester, detail: () async => throw const ForgeOffline('x'));

    expect(find.text('Could not reach GitHub.'), findsOneWidget);
    expect(find.text('Add the widget'), findsOneWidget);
  });

  testWidgets('unreadable CI costs the job list, not the description', (
    tester,
  ) async {
    await _pump(tester, checks: () async => throw const ForgeOffline('x'));

    expect(find.text('Could not reach GitHub.'), findsOneWidget);
    expect(find.text('Because it helps.'), findsOneWidget);
  });

  testWidgets('says when the request has moved past what is shown', (
    tester,
  ) async {
    await _pump(
      tester,
      detail: () async {
        final d = _detail();
        return d.copyWith(request: d.request.copyWith(headSha: 'f' * 40));
      },
    );
    expect(
      find.text(
        'The request has new commits since this review opened. Open it again to see them.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens the request in the browser by its number', (tester) async {
    final seen = await _pump(tester);

    await tester.tap(find.text('Open in browser'));
    await tester.pumpAndSettle();

    expect(seen.launched.single.toString(), 'https://github.com/o/r/pull/7');
  });

  testWidgets('a plain branch review asks the forge nothing', (tester) async {
    final seen = await _pump(tester, target: _target(pr: null));

    expect(seen.details, isEmpty);
    expect(seen.checks, isEmpty);
    expect(find.text('Add the thing'), findsNothing);
  });

  for (final width in [336.0, 520.0, 900.0]) {
    testWidgets('lays out without overflow at ${width}px', (tester) async {
      await _pump(
        tester,
        width: width,
        detail: () async => _detail(body: 'A long line ' * 40)
            .copyWith(request: _detail().request.copyWith(title: 'T ' * 60)),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('lint'), findsOneWidget);
    });
  }
}
