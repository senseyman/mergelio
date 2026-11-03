import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/forge/forge_host.dart';
import '../../domain/forge/models.dart';
import '../../domain/forge/pull_request_ref.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
import '../../state/forge_refresh.dart';
import '../../state/repo_actions.dart';
import '../../state/settings.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import 'forge_presentation.dart';
import 'sidebar_section.dart';

/// How a forge row checks its request out locally.
///
/// Overridable so a widget test can see what would have been checked out
/// without running git on the host.
final forgeCheckoutPullRequestProvider =
    Provider<Future<void> Function(String repoPath, ForgeKind kind, int n)>(
      (ref) =>
          (repoPath, kind, number) => ref
              .read(repoActionsProvider(repoPath))
              .checkoutPullRequest(kind, number),
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
    final gitlab = host.kind == ForgeKind.gitlab;

    final l = AppLocalizations.of(context);
    final ctl = ref.read(settingsProvider.notifier);
    final open = ref.watch(
      settingsProvider.select((s) => s.sectionOpen('pull-requests')),
    );
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
    final checkoutRequest = ref.watch(forgeCheckoutPullRequestProvider);

    return SidebarSection(
      id: 'pull-requests',
      icon: Icons.merge_type,
      label: gitlab ? l.forgeMergeRequests : l.forgePullRequests,
      // Null, not 0, until the fetch resolves — a 0 here would claim the
      // repository has none before it is actually known.
      count: panel?.valueOrNull?.pullRequests.length,
      emptyLabel: gitlab ? l.forgeNoMergeRequests : l.forgeNoPullRequests,
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
        if (!connected)
          ForgeMessageRow(
            text: gitlab ? l.forgeConnectHintGitlab : l.forgeConnectHint,
          ),
        ...?panel?.when(
          loading: () => const [ForgeLoadingRow()],
          error: (e, _) => [
            ForgeMessageRow(text: forgePanelMessage(e, l, host.kind)),
          ],
          data: (p) => p.pullRequests.isEmpty
              // Nothing to say here: an empty list with the section open and
              // connected is exactly the case [SidebarSection] itself already
              // renders via [emptyLabel] below. Saying it twice risked the
              // two copies drifting apart; only one needs to exist.
              ? const []
              : [
                  for (final pr in p.pullRequests)
                    _PullRequestRow(
                      // Identity, not position. The forge sorts by last
                      // update, so a comment on any request reshuffles this
                      // list — and an opened row whose state belongs to a
                      // slot would hand itself to whoever slid into it.
                      key: ValueKey(pr.number),
                      pr: pr,
                      badge: checkBadgeFor(p.checksBySha[pr.headSha]),
                      defaultBranch: p.defaultBranch,
                      failedRuns: forgeFailedRuns(p.checksBySha[pr.headSha]),
                      localBranch: pullRequestLocalBranch(host.kind, pr.number),
                      onCheckout: () =>
                          checkoutRequest(repoPath, host.kind, pr.number),
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
                                gitlab
                                    ? l.forgeCouldNotOpenMr
                                    : l.forgeCouldNotOpenPr,
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

class _PullRequestRow extends StatefulWidget {
  final PullRequest pr;
  final CheckBadge badge;
  final String? defaultBranch;
  final List<CheckRun> failedRuns;
  final VoidCallback onOpen;

  /// The branch [onCheckout] puts the request on, for the menu to name.
  final String localBranch;
  final VoidCallback onCheckout;

  const _PullRequestRow({
    super.key,
    required this.pr,
    required this.badge,
    required this.defaultBranch,
    required this.failedRuns,
    required this.onOpen,
    required this.localBranch,
    required this.onCheckout,
  });

  @override
  State<_PullRequestRow> createState() => _PullRequestRowState();
}

class _PullRequestRowState extends State<_PullRequestRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pr = widget.pr;
    final failed = widget.failedRuns;
    // Shortest first, so what runs off the end is the branch name: it is the
    // longest field and the one a reader can most afford to lose.
    final meta = forgeMetaLine([
      pr.author.login,
      forgeAgo(AppLocalizations.of(context), pr.updatedAt),
      forgeBranchLabel(pr, widget.defaultBranch),
    ]);
    // A click keeps opening the browser, as it always has; checking out is
    // the less common act, so it waits behind a right-click.
    return GestureDetector(
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: InkWell(
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  // The badge answers a different question from the row, so it
                  // takes the press itself rather than letting it reach the
                  // row's tap target and navigate away. Only when there is
                  // something to read: a green badge opens onto nothing.
                  if (failed.isEmpty)
                    _Badge(badge: widget.badge)
                  else
                    GestureDetector(
                      key: ValueKey('pr-checks-${pr.number}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: _Badge(badge: widget.badge),
                    ),
                ],
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    meta,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textFaint, fontSize: 11),
                  ),
                ),
              if (_expanded)
                for (final run in failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: Text(
                      run.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.danger, fontSize: 11),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, Offset at) {
    final l = AppLocalizations.of(context);
    PopupMenuItem<void> item(String label, VoidCallback onTap) => PopupMenuItem(
      height: 34,
      onTap: onTap,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
    return showContextMenu<void>(
      context: context,
      position: at,
      items: [
        item(l.forgeOpenInBrowser, widget.onOpen),
        item(l.forgeCheckoutLocally(widget.localBranch), widget.onCheckout),
      ],
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
