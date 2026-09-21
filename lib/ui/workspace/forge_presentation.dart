import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/tokens.dart';
import '../../domain/forge/forge_error.dart';
import '../../domain/forge/forge_host.dart';
import '../../domain/forge/models.dart';
import '../../l10n/gen/app_localizations.dart';

/// What a row draws for its CI state.
///
/// This is deliberately not the same enum as [ChecksOverall]: the summary
/// distinguishes outcomes the badge draws identically, and keeping them apart
/// means a new forge outcome cannot silently acquire a colour.
enum CheckBadge { none, running, success, failure, mixed }

/// The badge for [summary], or [CheckBadge.none] when a pull request has no CI
/// at all. Anything other than an all-green summary is never [CheckBadge.success].
CheckBadge checkBadgeFor(ChecksSummary? summary) {
  if (summary == null) return CheckBadge.none;
  return switch (summary.overall) {
    ChecksOverall.none => CheckBadge.none,
    ChecksOverall.running => CheckBadge.running,
    ChecksOverall.success => CheckBadge.success,
    ChecksOverall.failure => CheckBadge.failure,
    ChecksOverall.mixed => CheckBadge.mixed,
  };
}

/// What to show a person when a forge read failed.
///
/// Every branch returns this file's own words. The detail carried by
/// [ForgeOffline] and [ForgeMalformed] is deliberately dropped: it is written
/// for a log, and echoing it into the interface is how a secret eventually
/// reaches a screenshot.
String forgePanelMessage(Object error, AppLocalizations l) {
  if (error is ForgeUnauthenticated) return l.forgeErrUnauthenticated;
  if (error is ForgeRateLimited) {
    final at = error.resetAt;
    if (at == null) return l.forgeErrRateLimitedSoon;
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return l.forgeErrRateLimited('$hh:$mm');
  }
  if (error is ForgeNotVisible) return l.forgeErrNotVisible;
  if (error is ForgeOffline) return l.forgeErrOffline;
  if (error is ForgeServerFault) return l.forgeErrServer(error.status);
  return l.forgeErrMalformed;
}

/// Where a person goes to read pull request [number] on the web.
///
/// Built from the repository's own coordinates and an integer, never from a
/// URL the forge sent back, so no response can decide where the browser opens.
Uri pullRequestWebUrl(ForgeHost host, int number) =>
    Uri.https(host.host, '/${host.owner}/${host.repo}/pull/$number');

/// Where a person goes to read issue [number] on the web.
///
/// Built the same way, and from the same local coordinates, as
/// [pullRequestWebUrl] — but never down the same path: a forge numbers
/// issues and pull requests in one sequence yet serves them from separate
/// URLs, so an issue sent to the pull path opens a different page.
Uri issueWebUrl(ForgeHost host, int number) =>
    Uri.https(host.host, '/${host.owner}/${host.repo}/issues/$number');

/// How a forge row opens its web page.
///
/// Overridable so a test can watch what would have been opened, or force a
/// failure, without a real browser launch reaching a platform channel that a
/// widget test cannot answer. Shared by every forge section, so a row's tap
/// behaves the same wherever it lives.
final forgeLaunchUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => launchUrl,
);

/// One line of muted text standing in for rows: a hint, or a panel's error
/// in the words [forgePanelMessage] chose.
///
/// Shared so every forge section says its piece the same way. They were
/// separate copies once, identical by coincidence rather than by contract.
class ForgeMessageRow extends StatelessWidget {
  final String text;

  const ForgeMessageRow({super.key, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(
      text,
      style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
    ),
  );
}

/// What a forge section shows while its first read is in flight.
class ForgeLoadingRow extends StatelessWidget {
  const ForgeLoadingRow({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: SizedBox(
      width: 12,
      height: 12,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

/// How long ago [at] was, in the shortest form that still says something.
///
/// Deliberately terser than the prose the fetch prompt uses: this sits in a
/// sidebar row beside an author and, on a pull request, two branch names,
/// and the sidebar starts at 264 logical pixels. The largest whole unit
/// wins, so ninety minutes reads as an hour.
///
/// A timestamp ahead of this machine's clock reads as [forgeAgoNow] rather
/// than a negative age — forge and client clocks disagree routinely, and a
/// row claiming "-3h" would be worse than one admitting nothing. That falls
/// out of the first test rather than needing its own: a negative duration
/// has negative minutes, which is under one.
String? forgeAgo(AppLocalizations l, DateTime? at) {
  if (at == null) return null;
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return l.forgeAgoNow;
  if (d.inHours < 1) return l.forgeAgoMinutes(d.inMinutes);
  if (d.inDays < 1) return l.forgeAgoHours(d.inHours);
  return l.forgeAgoDays(d.inDays);
}

/// How a pull request's branches read on one line.
///
/// Names the target only when it is not the repository's trunk. Nearly every
/// request targets the trunk, so spelling it out on every row spends the
/// widest field in the line saying nothing — while the request that targets
/// a release branch is exactly the one worth noticing.
///
/// With [defaultBranch] unknown both are named: a redundant arrow costs a
/// little width, and guessing costs the reader the case that mattered.
String forgeBranchLabel(PullRequest pr, String? defaultBranch) =>
    pr.targetBranch == defaultBranch
    ? pr.sourceBranch
    : '${pr.sourceBranch} → ${pr.targetBranch}';

/// Joins a row's secondary facts, skipping whatever the forge left out.
///
/// One string rather than a row of widgets, so a long branch name ellipsises
/// instead of overflowing — the failure this sidebar has produced before.
/// Callers order the parts shortest-first for that reason: what runs off the
/// end is the tail.
String forgeMetaLine(List<String?> parts) =>
    parts.whereType<String>().where((p) => p.isNotEmpty).join(' · ');

/// The checks that failed on a ref, which are the only ones worth a row's
/// height. A reader looking at a red badge wants the name to open, not the
/// eleven jobs that passed.
///
/// Already in memory: the panel fetches full summaries to decide the badge,
/// so showing these costs no further requests.
List<CheckRun> forgeFailedRuns(ChecksSummary? summary) =>
    summary?.runs.where((r) => r.state == CheckState.failure).toList() ??
    const [];
