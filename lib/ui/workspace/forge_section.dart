import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/tokens.dart';
import '../../domain/forge/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
import '../../state/forge_refresh.dart';
import '../../state/settings_controller.dart';
import 'forge_presentation.dart';
import 'sidebar_section.dart';

/// How a pull request row opens its web page.
///
/// Overridable so a test can watch what would have been opened, or force a
/// failure, without a real browser launch reaching a platform channel that a
/// widget test cannot answer.
final forgeLaunchUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => launchUrl,
);

/// The repository's open pull requests, with what CI made of each one.
///
/// Absent entirely for a repository that is not on a supported forge: an
/// empty section would suggest there is something to connect, and there is
/// not.
class ForgePullRequestSection extends ConsumerWidget {
  final String repoPath;
  const ForgePullRequestSection({super.key, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(forgeHostProvider(repoPath)).valueOrNull;
    if (host == null) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final collapsed = ref.watch(
      settingsProvider.select((s) => s.collapsedSections),
    );
    final ctl = ref.read(settingsProvider.notifier);
    final open = !(collapsed['pull-requests'] ?? false);
    // A collapsed section shows nothing, so watching the panel while
    // collapsed would spend a forge fetch on rows nobody can see. The watch
    // only starts once the section is actually open, and stops (Riverpod
    // disposes the family member once nothing watches it) the moment it is
    // collapsed again.
    final panel = open ? ref.watch(pullRequestPanelProvider(repoPath)) : null;
    final connected =
        ref.watch(forgeTokenProvider(repoPath)).valueOrNull != null;
    // A press while one is already running would invalidate the panel a
    // second time mid-flight, spending another ~21-request budget for
    // nothing. Disabling the control is also what tells the person the
    // press landed on a refresh already under way, not that it did nothing.
    final refreshing = panel?.isLoading ?? false;
    final launch = ref.watch(forgeLaunchUrlProvider);

    return SidebarSection(
      id: 'pull-requests',
      icon: Icons.merge_type,
      label: l.forgePullRequests,
      // Null, not 0, until the fetch resolves — a 0 here would claim the
      // repository has none before it is actually known.
      count: panel?.valueOrNull?.pullRequests.length,
      emptyLabel: l.forgeNoPullRequests,
      open: open,
      onToggle: () => ctl.toggleSection('pull-requests'),
      trailing: IconButton(
        icon: Icon(Icons.refresh, size: 14, color: context.tokens.textFaint),
        tooltip: l.forgeRefresh,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        // Goes through the scheduler rather than a bare invalidate, so a
        // manual refresh also pushes the next scheduled tick out a full
        // interval — otherwise a background tick could land moments later
        // and spend the same rate-limit budget again for nothing.
        onPressed: refreshing
            ? null
            : () => ref.read(forgeRefreshProvider).refreshNow(repoPath),
      ),
      children: [
        if (!connected) _HintRow(text: l.forgeConnectHint),
        ...?panel?.when(
          loading: () => const [_LoadingRow()],
          error: (e, _) => [_MessageRow(text: forgePanelMessage(e, l))],
          data: (p) => p.pullRequests.isEmpty
              // Nothing to say here: an empty list with the section open and
              // connected is exactly the case [SidebarSection] itself already
              // renders via [emptyLabel] below. Saying it twice risked the
              // two copies drifting apart; only one needs to exist.
              ? const []
              : [
                  for (final pr in p.pullRequests)
                    _PullRequestRow(
                      pr: pr,
                      badge: checkBadgeFor(p.checksBySha[pr.headSha]),
                      // The URL is built from the locally-resolved [host]
                      // and a plain int, never from a string the forge sent
                      // back — nothing here can redirect this tap anywhere
                      // the local git remote did not already point.
                      onOpen: () async {
                        final opened = await launch(
                          pullRequestWebUrl(host, pr.number),
                        );
                        // launchUrl returning false means nothing handled
                        // the request — no browser configured, for
                        // instance — and the tap would otherwise look like
                        // it did nothing at all.
                        if (!opened) {
                          ref
                              .read(toastProvider.notifier)
                              .show(
                                l.forgeCouldNotOpenPr,
                                kind: ToastKind.error,
                              );
                        }
                      },
                    ),
                ],
        ),
      ],
    );
  }
}

class _PullRequestRow extends StatelessWidget {
  final PullRequest pr;
  final CheckBadge badge;
  final VoidCallback onOpen;

  const _PullRequestRow({
    required this.pr,
    required this.badge,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text(
              '#${pr.number}',
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pr.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textPrimary, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            _Badge(badge: badge),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final CheckBadge badge;
  const _Badge({required this.badge});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return switch (badge) {
      CheckBadge.none => const SizedBox(width: 14),
      CheckBadge.success => Icon(Icons.check, size: 14, color: t.success),
      CheckBadge.failure => Icon(Icons.close, size: 14, color: t.danger),
      CheckBadge.running ||
      CheckBadge.mixed => Icon(Icons.circle, size: 8, color: t.textMuted),
    };
  }
}

class _HintRow extends StatelessWidget {
  final String text;
  const _HintRow({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(
      text,
      style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
    ),
  );
}

class _MessageRow extends StatelessWidget {
  final String text;
  const _MessageRow({required this.text});

  @override
  Widget build(BuildContext context) => _HintRow(text: text);
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: SizedBox(
      height: 12,
      width: 12,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}
