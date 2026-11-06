import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/notify/desktop_notifier.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge_notify_diff.dart';

PullRequest pr(
  int n, {
  PullRequestState state = PullRequestState.open,
  String title = 'Fix thing',
  String source = 'feat/x',
  String target = 'main',
}) => PullRequest(
  number: n,
  title: title,
  state: state,
  author: const ForgeUser(login: 'a'),
  sourceBranch: source,
  targetBranch: target,
  headSha: 'sha$n',
  updatedAt: DateTime(2026, 1, 1),
);

typedef Label = ({String branch, int? prNumber, String? targetBranch});

ForgeSnapshot snap({
  List<PullRequest> prs = const [],
  Map<String, ChecksOverall> ci = const {},
  Set<String> notified = const {},
}) => ForgeSnapshot(
  maxPrNumber: prs.fold(0, (m, p) => p.number > m ? p.number : m),
  openPrs: {for (final p in prs) p.number: p},
  ciBySha: ci,
  notifiedCi: notified,
);

Map<int, PullRequest> prMap(List<PullRequest> l) => {
  for (final p in l) p.number: p,
};

final _lastPr = pr(5);

void main() {
  group('diffForgeSnapshots', () {
    test('seed emits nothing and records terminal states', () {
      final r = diffForgeSnapshots(
        prev: const ForgeSnapshot.empty(),
        openPrs: prMap([pr(12)]),
        ciBySha: {
          'a': ChecksOverall.success,
          'b': ChecksOverall.failure,
          'c': ChecksOverall.running,
          'd': ChecksOverall.mixed,
          'e': ChecksOverall.none,
        },
        shaLabels: const {},
        seed: true,
      );
      expect(r.events, isEmpty);
      expect(r.notifiedCi, {'a:success', 'b:failure', 'd:mixed'});
    });

    test('new higher-numbered PR is opened', () {
      final r = diffForgeSnapshots(
        prev: snap(prs: [pr(10)]),
        openPrs: prMap([pr(10), pr(12)]),
        ciBySha: const {},
        shaLabels: const {},
        seed: false,
      );
      expect(r.events, hasLength(1));
      final e = r.events.single as PrOpened;
      expect(e.pr.number, 12);
    });

    test('an old PR bumped into the page is not opened', () {
      final r = diffForgeSnapshots(
        prev: snap(prs: [pr(10)]),
        openPrs: prMap([pr(5), pr(10)]),
        ciBySha: const {},
        shaLabels: const {},
        seed: false,
      );
      expect(r.events, isEmpty);
    });

    test('a PR equal to the previous maximum is not opened', () {
      final r = diffForgeSnapshots(
        prev: snap(prs: [pr(10)]),
        openPrs: prMap([pr(10)]),
        ciBySha: const {},
        shaLabels: const {},
        seed: false,
      );
      expect(r.events, isEmpty);
    });

    test('a number between existing ones that is new is not opened', () {
      final r = diffForgeSnapshots(
        prev: snap(prs: [pr(3), pr(10)]),
        openPrs: prMap([pr(3), pr(7), pr(10)]),
        ciBySha: const {},
        shaLabels: const {},
        seed: false,
      );
      expect(r.events, isEmpty);
    });

    test('a PR that disappears is gone', () {
      final r = diffForgeSnapshots(
        prev: snap(prs: [pr(10), pr(11)]),
        openPrs: prMap([pr(11)]),
        ciBySha: const {},
        shaLabels: const {},
        seed: false,
      );
      expect(r.events, hasLength(1));
      final e = r.events.single as PrGone;
      expect(e.number, 10);
      expect(e.last.title, 'Fix thing');
    });

    test('running to failure finishes once, never twice', () {
      const labels = <String, Label>{
        'a': (branch: 'feat/x', prNumber: 12, targetBranch: 'main'),
      };
      final prev = snap(ci: {'a': ChecksOverall.running});
      final first = diffForgeSnapshots(
        prev: prev,
        openPrs: const {},
        ciBySha: {'a': ChecksOverall.failure},
        shaLabels: labels,
        seed: false,
      );
      final e = first.events.single as CiFinished;
      expect(e.sha, 'a');
      expect(e.state, ChecksOverall.failure);
      expect(e.branch, 'feat/x');
      expect(e.prNumber, 12);
      expect(e.targetBranch, 'main');

      final again = diffForgeSnapshots(
        prev: snap(
          ci: {'a': ChecksOverall.failure},
          notified: first.notifiedCi,
        ),
        openPrs: const {},
        ciBySha: {'a': ChecksOverall.failure},
        shaLabels: labels,
        seed: false,
      );
      expect(again.events, isEmpty);
      expect(again.notifiedCi, first.notifiedCi);
    });

    test('a new sha first seen already green finishes', () {
      final r = diffForgeSnapshots(
        prev: snap(prs: [pr(10)]),
        openPrs: prMap([pr(10)]),
        ciBySha: {'b': ChecksOverall.success},
        shaLabels: const {
          'b': (branch: 'main', prNumber: null, targetBranch: null),
        },
        seed: false,
      );
      final e = r.events.single as CiFinished;
      expect(e.sha, 'b');
      expect(e.state, ChecksOverall.success);
      expect(e.prNumber, isNull);
      expect(r.notifiedCi, {'b:success'});
    });

    test('same sha flipping to a different terminal state fires again', () {
      final r = diffForgeSnapshots(
        prev: snap(ci: {'a': ChecksOverall.success}, notified: {'a:success'}),
        openPrs: const {},
        ciBySha: {'a': ChecksOverall.failure},
        shaLabels: const {
          'a': (branch: 'x', prNumber: null, targetBranch: null),
        },
        seed: false,
      );
      expect((r.events.single as CiFinished).state, ChecksOverall.failure);
      expect(r.notifiedCi, {'a:success', 'a:failure'});
    });

    test('mixed, running and none stay silent', () {
      final r = diffForgeSnapshots(
        prev: const ForgeSnapshot.empty(),
        openPrs: const {},
        ciBySha: {
          'a': ChecksOverall.mixed,
          'b': ChecksOverall.running,
          'c': ChecksOverall.none,
        },
        shaLabels: const {
          'a': (branch: 'x', prNumber: null, targetBranch: null),
          'b': (branch: 'x', prNumber: null, targetBranch: null),
          'c': (branch: 'x', prNumber: null, targetBranch: null),
        },
        seed: false,
      );
      expect(r.events, isEmpty);
      expect(r.notifiedCi, {'a:mixed'});
    });

    test('a PR already open is not opened even above a stale mark', () {
      final r = diffForgeSnapshots(
        prev: ForgeSnapshot(
          openPrs: prMap([pr(12)]),
          ciBySha: const {},
          notifiedCi: const {},
        ),
        openPrs: prMap([pr(12)]),
        ciBySha: const {},
        shaLabels: const {},
        seed: false,
      );
      expect(r.events, isEmpty);
    });

    test('a final sha without a label is neither reported nor recorded', () {
      final r = diffForgeSnapshots(
        prev: const ForgeSnapshot.empty(),
        openPrs: const {},
        ciBySha: {'a': ChecksOverall.failure},
        shaLabels: const {},
        seed: false,
      );
      expect(r.events, isEmpty);
      expect(r.notifiedCi, isEmpty);
    });

    test('draft to open on the same number is silent', () {
      final r = diffForgeSnapshots(
        prev: snap(prs: [pr(10, state: PullRequestState.draft)]),
        openPrs: prMap([pr(10)]),
        ciBySha: const {},
        shaLabels: const {},
        seed: false,
      );
      expect(r.events, isEmpty);
    });

    test('a seeded repo with no PRs reports the first one as opened', () {
      final seeded = diffForgeSnapshots(
        prev: const ForgeSnapshot.empty(),
        openPrs: const {},
        ciBySha: const {},
        shaLabels: const {},
        seed: true,
      );
      expect(seeded.maxPrNumber, 0);
      final r = diffForgeSnapshots(
        prev: ForgeSnapshot(
          openPrs: const {},
          ciBySha: const {},
          notifiedCi: seeded.notifiedCi,
          maxPrNumber: seeded.maxPrNumber,
        ),
        openPrs: prMap([pr(5)]),
        ciBySha: const {},
        shaLabels: const {},
        seed: false,
      );
      expect((r.events.single as PrOpened).pr.number, 5);
      expect(r.maxPrNumber, 5);
    });

    test(
      'closed PRs leave the high-water mark so a reappearance is silent',
      () {
        final seeded = diffForgeSnapshots(
          prev: const ForgeSnapshot.empty(),
          openPrs: prMap([pr(3), pr(4)]),
          ciBySha: const {},
          shaLabels: const {},
          seed: true,
        );
        expect(seeded.maxPrNumber, 4);
        final closed = diffForgeSnapshots(
          prev: ForgeSnapshot(
            openPrs: prMap([pr(3), pr(4)]),
            ciBySha: const {},
            notifiedCi: seeded.notifiedCi,
            maxPrNumber: seeded.maxPrNumber,
          ),
          openPrs: const {},
          ciBySha: const {},
          shaLabels: const {},
          seed: false,
        );
        expect(closed.events.whereType<PrGone>().map((e) => e.number), [3, 4]);
        expect(closed.events, hasLength(2));
        expect(closed.maxPrNumber, 4);
        final back = diffForgeSnapshots(
          prev: ForgeSnapshot(
            openPrs: const {},
            ciBySha: const {},
            notifiedCi: closed.notifiedCi,
            maxPrNumber: closed.maxPrNumber,
          ),
          openPrs: prMap([pr(4)]),
          ciBySha: const {},
          shaLabels: const {},
          seed: false,
        );
        expect(back.events, isEmpty);
      },
    );
  });

  group('renderForgeEvents', () {
    final l = lookupAppLocalizations(const Locale('en'));

    List<AppNotification> render(
      List<(ForgeEvent, PrGoneOutcome?)> events, {
      ForgeKind kind = ForgeKind.github,
    }) => renderForgeEvents(
      l,
      repoPath: '/r/mergelio',
      repoName: 'mergelio',
      kind: kind,
      events: events,
    );

    (ForgeEvent, PrGoneOutcome?) opened(int n) => (PrOpened(pr(n)), null);

    test('up to the threshold stays individual', () {
      final out = render([opened(1), opened(2), opened(3)]);
      expect(out, hasLength(3));
      expect(out.every((n) => n.title == 'mergelio'), isTrue);
      expect(out.first.body, 'PR #1 opened: Fix thing');
      expect(out.first.target.prNumber, 1);
      expect(out.first.target.kind, ForgeKind.github);
      expect(out.first.target.targetBranch, 'main');
      expect(out.first.target.repoPath, '/r/mergelio');
    });

    test('over the threshold collapses into one repo-level notification', () {
      final out = render([
        opened(1),
        opened(2),
        (PrGone(5, _lastPr), PrGoneOutcome.merged),
        (const CiFinished('a', ChecksOverall.failure, 'x', null, null), null),
      ]);
      expect(out, hasLength(1));
      expect(out.single.title, 'mergelio');
      expect(
        out.single.body,
        '2 PRs opened, 1 PR closed, CI failed on 1 commit',
      );
      expect(out.single.target.repoPath, '/r/mergelio');
      expect(out.single.target.prNumber, isNull);
      expect(out.single.target.kind, isNull);
      expect(out.single.target.targetBranch, isNull);
    });

    test('batch uses MR wording on GitLab and lists passes too', () {
      final out = render([
        opened(1),
        opened(2),
        (const CiFinished('a', ChecksOverall.success, 'x', null, null), null),
        (const CiFinished('b', ChecksOverall.success, 'x', null, null), null),
      ], kind: ForgeKind.gitlab);
      expect(out.single.body, '2 MRs opened, CI passed on 2 commits');
    });

    test('GitLab ref is !N and GitHub is #N', () {
      expect(
        render([opened(7)], kind: ForgeKind.gitlab).single.body,
        'MR !7 opened: Fix thing',
      );
      expect(render([opened(7)]).single.body, 'PR #7 opened: Fix thing');
    });

    test('PrGone has a text per outcome', () {
      String body(PrGoneOutcome o, {ForgeKind k = ForgeKind.github}) =>
          render([(PrGone(9, _lastPr), o)], kind: k).single.body;
      expect(body(PrGoneOutcome.merged), 'PR #9 merged');
      expect(body(PrGoneOutcome.closed), 'PR #9 closed');
      expect(body(PrGoneOutcome.unknown), 'PR #9 no longer open');
      expect(body(PrGoneOutcome.merged, k: ForgeKind.gitlab), 'MR !9 merged');
    });

    test('CiFinished tied to a PR carries the PR target', () {
      final n = render([
        (
          const CiFinished('a', ChecksOverall.failure, 'feat/x', 12, 'main'),
          null,
        ),
      ]).single;
      expect(n.body, 'CI failed on feat/x (PR #12)');
      expect(n.target.prNumber, 12);
      expect(n.target.targetBranch, 'main');
      expect(n.target.kind, ForgeKind.github);
    });

    test('CiFinished without a PR targets only the repo', () {
      final n = render([
        (
          const CiFinished('a', ChecksOverall.success, 'main', null, null),
          null,
        ),
      ]).single;
      expect(n.body, 'CI passed on main');
      expect(n.target.prNumber, isNull);
      expect(n.target.kind, isNull);
    });
  });
}
