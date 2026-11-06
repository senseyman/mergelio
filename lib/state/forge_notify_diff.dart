import '../domain/forge/forge_host.dart';
import '../domain/forge/models.dart';
import '../domain/notify/desktop_notifier.dart';
import '../l10n/gen/app_localizations.dart';

/// More events than this in one repo and one tick collapse into a single
/// notification, so a busy repo cannot bury the desktop.
const kForgeBatchThreshold = 3;

/// What the watcher last saw on a repo's forge. Held in memory only.
class ForgeSnapshot {
  const ForgeSnapshot({
    required this.openPrs,
    required this.ciBySha,
    required this.notifiedCi,
  });

  const ForgeSnapshot.empty()
    : openPrs = const {},
      ciBySha = const {},
      notifiedCi = const {};

  final Map<int, PullRequest> openPrs;
  final Map<String, ChecksOverall> ciBySha;

  /// `'$sha:$state'` for every terminal CI result already reported (or seen
  /// while seeding), so the same result never notifies twice.
  final Set<String> notifiedCi;
}

sealed class ForgeEvent {
  const ForgeEvent();
}

class PrOpened extends ForgeEvent {
  const PrOpened(this.pr);
  final PullRequest pr;
}

class PrGone extends ForgeEvent {
  const PrGone(this.number, this.last);
  final int number;

  /// The request as last seen open.
  final PullRequest last;
}

class CiFinished extends ForgeEvent {
  const CiFinished(
    this.sha,
    this.state,
    this.branch,
    this.prNumber,
    this.targetBranch,
  );
  final String sha;
  final ChecksOverall state;
  final String branch;
  final int? prNumber;
  final String? targetBranch;
}

enum PrGoneOutcome { merged, closed, unknown }

bool _isFinal(ChecksOverall s) =>
    s == ChecksOverall.success || s == ChecksOverall.failure;

/// Compares what the forge shows now against [prev].
///
/// With [seed] (the first look at a repo) nothing is reported; the current
/// terminal CI results are only recorded. A request counts as opened only
/// when its number exceeds every number in [prev]: numbers only grow within a
/// repo, so an old request reshuffled into the list page is not news.
/// `mixed` (cancelled or skipped) is final but silent; `none` and `running`
/// are not final.
({List<ForgeEvent> events, Set<String> notifiedCi}) diffForgeSnapshots({
  required ForgeSnapshot prev,
  required Map<int, PullRequest> openPrs,
  required Map<String, ChecksOverall> ciBySha,
  required Map<String, ({String branch, int? prNumber, String? targetBranch})>
  shaLabels,
  required bool seed,
}) {
  final notified = {...prev.notifiedCi};
  final events = <ForgeEvent>[];

  if (!seed && prev.openPrs.isNotEmpty) {
    final prevMax = prev.openPrs.keys.reduce((a, b) => a > b ? a : b);
    final numbers = openPrs.keys.toList()..sort();
    for (final n in numbers) {
      if (n > prevMax) {
        events.add(PrOpened(openPrs[n]!));
      }
    }
    final gone = prev.openPrs.keys.where((n) => !openPrs.containsKey(n));
    for (final n in gone.toList()..sort()) {
      events.add(PrGone(n, prev.openPrs[n]!));
    }
  }

  for (final e in ciBySha.entries) {
    if (!_isFinal(e.value)) continue;
    final key = '${e.key}:${e.value.name}';
    if (notified.contains(key)) continue;
    if (seed) {
      notified.add(key);
      continue;
    }
    if (e.value == ChecksOverall.success || e.value == ChecksOverall.failure) {
      final label = shaLabels[e.key];
      if (label == null) continue;
      notified.add(key);
      events.add(
        CiFinished(
          e.key,
          e.value,
          label.branch,
          label.prNumber,
          label.targetBranch,
        ),
      );
    }
  }
  return (events: events, notifiedCi: notified);
}

/// Turns [events] into notifications titled with [repoName]. More than
/// [kForgeBatchThreshold] events collapse into one that targets only the repo.
List<AppNotification> renderForgeEvents(
  AppLocalizations l, {
  required String repoPath,
  required String repoName,
  required ForgeKind kind,
  required List<(ForgeEvent, PrGoneOutcome?)> events,
}) {
  final mr = kind == ForgeKind.gitlab;
  String ref(int n) => mr ? '!$n' : '#$n';

  if (events.length > kForgeBatchThreshold) {
    var opened = 0, closed = 0, failed = 0, passed = 0;
    for (final (e, _) in events) {
      switch (e) {
        case PrOpened():
          opened++;
        case PrGone():
          closed++;
        case CiFinished(:final state):
          if (state == ChecksOverall.failure) {
            failed++;
          } else {
            passed++;
          }
      }
    }
    final parts = <String>[
      if (opened > 0)
        mr ? l.ntfBatchOpenedMr(opened) : l.ntfBatchOpened(opened),
      if (closed > 0)
        mr ? l.ntfBatchClosedMr(closed) : l.ntfBatchClosed(closed),
      if (failed > 0) l.ntfBatchCiFailed(failed),
      if (passed > 0) l.ntfBatchCiPassed(passed),
    ];
    return [
      AppNotification(
        title: repoName,
        body: l.ntfBatch(parts.join(', ')),
        target: NotificationTarget(repoPath: repoPath),
      ),
    ];
  }

  return [
    for (final (e, outcome) in events)
      switch (e) {
        PrOpened(:final pr) => AppNotification(
          title: repoName,
          body: mr
              ? l.ntfMrOpened(ref(pr.number), pr.title)
              : l.ntfPrOpened(ref(pr.number), pr.title),
          target: NotificationTarget(
            repoPath: repoPath,
            kind: kind,
            prNumber: pr.number,
            targetBranch: pr.targetBranch,
          ),
        ),
        PrGone(:final number, :final last) => AppNotification(
          title: repoName,
          body: switch (outcome ?? PrGoneOutcome.unknown) {
            PrGoneOutcome.merged =>
              mr ? l.ntfMrMerged(ref(number)) : l.ntfPrMerged(ref(number)),
            PrGoneOutcome.closed =>
              mr ? l.ntfMrClosed(ref(number)) : l.ntfPrClosed(ref(number)),
            PrGoneOutcome.unknown =>
              mr ? l.ntfMrGone(ref(number)) : l.ntfPrGone(ref(number)),
          },
          target: NotificationTarget(
            repoPath: repoPath,
            kind: kind,
            prNumber: number,
            targetBranch: last.targetBranch,
          ),
        ),
        CiFinished() => _renderCi(l, e, repoPath, repoName, kind, ref),
      },
  ];
}

AppNotification _renderCi(
  AppLocalizations l,
  CiFinished e,
  String repoPath,
  String repoName,
  ForgeKind kind,
  String Function(int) ref,
) {
  final passed = e.state == ChecksOverall.success;
  final n = e.prNumber;
  final body = n == null
      ? (passed ? l.ntfCiPassed(e.branch) : l.ntfCiFailed(e.branch))
      : (passed
            ? l.ntfCiPassedPr(e.branch, _prefixed(kind, ref(n)))
            : l.ntfCiFailedPr(e.branch, _prefixed(kind, ref(n))));
  return AppNotification(
    title: repoName,
    body: body,
    target: n == null
        ? NotificationTarget(repoPath: repoPath)
        : NotificationTarget(
            repoPath: repoPath,
            kind: kind,
            prNumber: n,
            targetBranch: e.targetBranch,
          ),
  );
}

String _prefixed(ForgeKind kind, String ref) =>
    '${kind == ForgeKind.gitlab ? 'MR' : 'PR'} $ref';
