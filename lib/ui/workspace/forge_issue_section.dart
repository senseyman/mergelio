import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/forge/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
import '../../state/forge_refresh.dart';
import '../../state/settings.dart';
import '../../state/settings_controller.dart';
import 'forge_presentation.dart';
import 'sidebar_section.dart';

/// A repository's open issues.
///
/// Absent entirely for a repository not on a supported forge, for the same
/// reason [ForgePullRequestSection] is: an empty section here would suggest
/// something to connect, when there is nothing.
///
/// Deliberately carries no connect-token hint of its own — the pull request
/// section above it already shows one for the same repository, and a second
/// copy would only be noise.
class ForgeIssueSection extends ConsumerWidget {
  final String repoPath;
  const ForgeIssueSection({super.key, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(forgeHostProvider(repoPath)).valueOrNull;
    if (host == null) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final ctl = ref.read(settingsProvider.notifier);
    final open = ref.watch(
      settingsProvider.select((s) => s.sectionOpen('issues')),
    );
    // A collapsed section shows nothing, so watching the panel while
    // collapsed would spend a forge fetch on rows nobody can see. The watch
    // only starts once the section is actually open, and stops (Riverpod
    // disposes the family member once nothing watches it) the moment it is
    // collapsed again.
    final panel = open ? ref.watch(issuePanelProvider(repoPath)) : null;
    // A press while one is already running would invalidate the panel a
    // second time mid-flight, spending another request for nothing.
    // Disabling the control is also what tells the person the press landed
    // on a refresh already under way, not that it did nothing.
    final refreshing = panel?.isLoading ?? false;
    final launch = ref.watch(forgeLaunchUrlProvider);

    return SidebarSection(
      id: 'issues',
      icon: Icons.circle_outlined,
      label: l.forgeIssues,
      // Null, not 0, until the fetch resolves — 0 here would claim the
      // repository has none before that is actually known.
      count: panel?.valueOrNull?.length,
      emptyLabel: l.forgeNoIssues,
      open: open,
      onToggle: () => ctl.toggleSection('issues'),
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
        ...?panel?.when(
          loading: () => const [ForgeLoadingRow()],
          error: (e, _) => [ForgeMessageRow(text: forgePanelMessage(e, l))],
          data: (issues) => issues.isEmpty
              // Nothing to say here: an empty list with the section open is
              // exactly the case [SidebarSection] itself already renders via
              // [emptyLabel] below. Saying it twice risked the two copies
              // drifting apart; only one needs to exist.
              ? const []
              : [
                  for (final issue in issues)
                    _IssueRow(
                      issue: issue,
                      // Built from the locally-resolved [host] and a plain
                      // int, never from a string the forge sent back —
                      // nothing here can redirect this tap anywhere the
                      // local git remote did not already point.
                      onOpen: () async {
                        final opened = await launch(
                          issueWebUrl(host, issue.number),
                        );
                        // launchUrl returning false means nothing handled
                        // the request — no browser configured, for instance
                        // — and the tap would otherwise look like it did
                        // nothing at all.
                        if (!opened) {
                          ref
                              .read(toastProvider.notifier)
                              .show(
                                l.forgeCouldNotOpenIssue,
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

class _IssueRow extends StatelessWidget {
  final Issue issue;
  final VoidCallback onOpen;

  const _IssueRow({required this.issue, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#${issue.number}',
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    issue.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                  ),
                ),
              ],
            ),
            // Kept on a line of its own, and only here — never on a pull
            // request row — so a long label list never crowds the title out.
            if (issue.labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  issue.labels.join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textFaint, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
