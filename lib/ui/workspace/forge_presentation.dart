import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
